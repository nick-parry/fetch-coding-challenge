#!/bin/bash
################################################################################
# BASH!!! I could have done this in go or python, but this is the one I thought
# this would be the most challenging in today. Sorry if you hate this. :)
# I tried to comment extensively in here describing what exactly I did. I think
# this is mostly my normal style, though maybe a touch verbose as this is a coding
# challenge.
#
# An overview of the threaded approach I took here is as follows:
# - Start up a health check thread for every element found in the input.yaml
# - Start up an output thread that will aggregate, calculate, and output in the
#   desired format(plus color)
# - Each subprocess that is started is written to a pid file and should be cleaned
#   up upon script exit. E.G. I confirmed that after a control+c, there were no
#   pids running wild and free on my box.
#
# NP 09-24-24
################################################################################
# Colors to add some fun.
color_reset="\e[0m"
color_red="\e[31m"
color_green="\e[32m"

# The file we will keep track of pids we wait on
pidListToWait="data/pidList"
# The file where we keep track of pids to kill, but not wait for.
pidListToClean="data/pidListToCleanse"
# The time we sleep between each check
INTERVAL=15

# Logging methods(only used for debugging, but kept to show how I got to now)
function log() {
    echo -e "$(date +%c) - $*" | tee -a data/log.log
}
function die() {
    log "${color_red}ERROR${color_reset}: $*"
    cleanUp
    exit 1
}
# A method to fail, but not rm stuff.
function dieNoCleanup() {
    log "${color_red}ERROR${color_reset}: $*"
    exit 2
}

# A basic usage function to display a help message if requested/or no args present
function usage(){
    echo -e "$(basename "$0") - A coding challenge based health checker of sorts. Usage:"
    echo -e "Must provide a single arg which is a path to a valid yaml config file. Config"
    echo -e "is described here: https://fetch-hiring.s3.us-east-1.amazonaws.com/site-reliability-engineer/health-check.pdf"

    exit 0
}

# A cleanup method
trap cleanUp INT
function cleanUp(){ 
    if [[ -f $pidListToWait ]];then
        # Stop all child processes that we started here, and ignore errors
        cat $pidListToWait 2>/dev/null | xargs kill 2>/dev/null
    fi 
    if [[ -f $pidListToClean ]];then
        # Stop all child processes that we started here, and ignore errors
        cat $pidListToClean 2>/dev/null | xargs kill 2>/dev/null
    fi 
    # Move the data directory for later review if you want. Sorry if this is in
    # fact cruft for you to manually clean up later. But since I kept a lot of the
    # stuff and wrote is as json, we could extend this later on. In small ways like
    # calculating availability per url in addition to domain, or printing out an average
    # page download time, etc.
    mv data "$(date +%s)" 2>/dev/null
}


# Check for the required dependencies
function preFlightCheck() {
    # Make sure we have the tools we need
    which jq 2>&1 >/dev/null || die "Need to have jq in your path."
    which yq 2>&1 >/dev/null || die "Need to have yq in your path."
    which bc 2>&1 >/dev/null || die "Need to have bc in your path."
    which curl 2>&1 >/dev/null || die "Need to have curl in your path."

    # Make sure that the input file is valid yaml
    test -f "$INPUTFILE" || die "$INPUTFILE isn't a readable file"
    cat "$INPUTFILE" | yq . 2>&1 >/dev/null || die "Failed to parse input file($INPUTFILE) as valid yaml."

    # Make sure that we have a data dir to scratch stuff in.
    # I know that the problem statement said that persisting the data was not required.
    # I did it this way as this is the easiest method I have found when dealing with
    # data across subprocesses in bash. However, if you try to run this script from
    # a directory on your local machine where you have an important `data` directory
    # present, it will fail and not delete it. But probably best to just run it with
    # this repo as your CWD. Then you can delete it all and move on with you life. :)
    test -d ./data && dieNoCleanup "'./data' directory already exists. Need that here for scratch space."
    mkdir -p data/checks
}

# The health check function. Takes a single json input element as the arg. Parses out the
# url, headers, etc and then will execute the check via curl. Writes each check to a url
# specific file.
function healthCheck() {
    # Collect the various details for this health check item as some parts are optional.
    # Normally, this would be better to parse out in a layer up from here. Probably using
    # a data class to contain each element and sane defaults. But not today.
    # Get the name(stashed for fun, but not used in any real way)
    name="$(echo "$1" | jq -r .name)"
    # Get the URL. This is required, though I opted to be very lazy in mostly all of my input
    # validation here. I would hopefully do better depending on the authors of that input.yaml file.
    url="$(echo "$1" | jq -r .url)"
    # Get the domain from the url(used for aggregating upness/downness)
    domain="$(echo "$url" | cut -d / -f 3)"
    method="$(echo "$1" | jq -r .method)"
    # Use the method provided, but default to an explicit GET
    if [[ $method != "null" ]];then
        curl_method="-X ${method}"
    else
        curl_method="-X GET"
    fi 

    # Build the headers as curl args based on the presence of headers list in the yaml
    # No validation here. Again. The sample values work, but I think it is pretty fragile.
    # And didn't bother even testing this very much.
    headers="$(echo "$1" | jq .headers)"
    if [[ $headers != "null" ]];then
        # Using the output of this loop as the variable means that errors here will mess it
        # up. So no errors allowed in this yaml parsing. Haha. Fragile.
        curl_headers="$(echo "$headers" | jq -r | while read -r l;do
            # Some gross json parsing via grep here to build one "-H" arg for each header
            if [[ $l == "}" || $l == "{" || $l == ".*user-agent.*" ]];then
                continue
            fi
            # Need to skip the user-agent header if present. We will get that directly
            # from the config, or set a default one later on.
            if [[ $(echo "$l" | grep -i 'user-agent') ]];then
                continue
            fi
            # Since this is a key/value already, lets just assume it's perfect and
            # go for it. :)
            echo -H "'$(echo "$l" | sed 's/"//g' | sed 's/,$//')'"
        done)"
    fi
    # Set the user agent, or use a default one if none was set.
    useragent="$(echo "$1" | jq -r '.headers["user-agent"]')"
    if [[ $useragent != "null" ]];then
        curl_ua="-A '${useragent}'"
    else
        # A default user agent makes sense here to me. Useful for serverside things
        # like determining real vs bot traffic and the like.
        curl_ua="-A 'fetch-synthetic-monitor'"
    fi

    # Set the body field if it was present.
    body="$(echo "$1" | jq -r .body)"
    if [[ $body != "null" ]];then
        # Build the curl option for this post body. Again, fragile. Going to assume it is
        # json and ignore the validation that I might do for a production system.
        curl_data="-d $body"
    fi


    # Building the basic curl command. And trying to explain what it is I am doing here:
    # Ignore my curlrc, silent output, hand crafted json output of time, return code,
    # and url(after redirects), ignore the response body that was returned, follow redirects
    base_curl="curl -q -s \
        -w '{\"http_code\": %{http_code}, \"time_total\": %{time_total}, \"url_effective\": \"%{url_effective}\"}\n'\
        -o /dev/null \
        -L"
    # Lazy url encoding of sorts so we can keep stats on each individual check via url as filename
    # Again, fragile as the only char I am replacing here is the "/". So not secure/safe
    # as I am not exactly sure what something like whitespace in the url would do here. :|
    filepath="data/checks/$(echo "$url" | sed 's!/!_!g')"
    # Use a bash -c subprocess so the various args will be escaped properly.
    v="$(bash -c "$base_curl $curl_ua $url $curl_method $curl_headers $curl_data")"
    # Save the curl commands that were built in this file for troubleshooting later on.
    echo "$base_curl $curl_ua $url $curl_method $curl_headers $curl_data" >> data/curl_cmds
    
    # Determine if this is UP as defined as a 2xx and < 500 millis 
    http_code="$(echo "$v" | jq .http_code)"
    time_total="$(echo "$v" | jq .time_total)"
    if [[ $(echo "$http_code" | grep '2[0-9][0-9]') && $(echo "$time_total < .500" | bc) == 1 ]] ;then
        status="up"
    else
        status="down"
    fi
    # Write the output from curl, but include some other things like domain, status, name via jq
    echo "$v" | jq -c ". += {\"timestamp\": \"$(date +%s)\", \
    \"domain\": \"$domain\",\
    \"status\": \"$status\",\
    \"name\": \"$name\",\
    }" >> "$filepath"
}

# An entry point to the healthcheck thread
function thread() {
    # For testing, just a few loops will do
    #for i in {0..4}; do
    # No need to stop. Probably.
    while :; do
        # Do a healthcheck
        healthCheck "$1"
        # Then wait
        sleep $INTERVAL
    done
}

# A method to calculate and output results in the desired format. Plus colors though :)
# Runs in its own subprocess
function output(){
    # Make sure that the first round has completed since we aren't going to check
    # for new domains in this exercise.
    sleep $INTERVAL
    # Find the unique domains from the data we have
    # Note that this too is fragile as any json errors from jq would break this in
    # interesting ways. Probably?
    uniqueDomains="$(cat data/checks/* | jq -r .domain | sort -u)"

    # Now that we have the list of domains, we are going to start the output loop where
    # we do the calculation and print the output for each domain.
    while :; do
        for domain in $uniqueDomains;do
            # Find out how many requests we have made so far for this domain
            tryCount="$(cat data/checks/* | jq "select(.domain == \"$domain\")" -c | wc -l)"
            # Now find out how many requests we have made so far for this domain, where it was up
            upCount="$(cat data/checks/* | jq "select(.domain == \"$domain\") | select(.status == \"up\")" -c | wc -l)"
            # Calculate the percentage of uptime(rounded to the nearest int)
            availability="$(printf "%.0f\n" "$(echo "100 * ($upCount / $tryCount)" | bc -l)")"
            echo -e "${color_green}${domain}${color_reset} has ${color_green}${availability}%${color_reset} availability percentage"
        done
        # Then, wait until another round has been written. Probably. As this is
        # just a time based data aggregator, it will eventually not work the longer
        # it runs. Depending on the time that the curls take to execute, I think that
        # time is added onto each interval in the thread -> healthcheck route, but
        # not here? Anyways, bash things are quick to write with very little dependency
        # management in general. But a tad fragile.
        sleep $INTERVAL
    done
}


################################################################################
# Main
################################################################################
# Validate that we have input, print a help message if we don't.
if [[ -z $1 || $1 == "--help" || $1 == "-h" ]];then
    usage
else
    # Set the filename if it was present
    INPUTFILE="$1"
fi

preFlightCheck

# Start up a thread/subprocess(I use these terms interchangeably here because I can)
# for every healthcheck element in the input.yaml file. You will notice the odd
# yq -> jq stuff, this is because my latest version of yq doesn't have the compact
# option that jq has which makes it easy to
cat "$INPUTFILE" | yq -o json | jq .[] -c | while read -r line;do
    thread "$line" & 
    # Keep track of each of the pids we start so we can clean them up later
    echo "$!" >> $pidListToWait
done &
echo "$!" >> $pidListToWait
# Make sure that all of the sub-processes are started up before proceeding
sleep 2

# Now we need to start up the output thread for the calculation/aggregation and output
output &
# Note that we don't save this pid in the pids to wait for file, but in the pids to clean
echo $! >> $pidListToClean

# Wait for some stuff to finsh/get the kill signal. The official "wait" route
# won't work here since we are waiting for processes that are managed in the sub-shell
# of the while loop. :( Would be simple to just:
# wait -f $(cat $pidListToWait | xargs) 2>/dev/null
# But we can't, so we are going to do it the hard way.
while :; do
    # Check for pids, and if we stop finding any of them, we can assume all
    # the "threads" have finished and move on with our lives. Though, they will
    # all need to be cleansed with fire on a control+c event unless I set a limit
    # to the number of iterations it will run on its own in the thread function.
    for pid in $(cat $pidListToWait 2>/dev/null);do
        if [[ $(ps -ef | grep $pid | grep -v 'grep\|vim') ]];then
            echo 1
        else
            echo 0
        fi
    # So if we find no more pids from the pid list, we can stop looking, otherwise
    # check every few seconds and see if we are done yet.
    done  | grep 1 -q || break && sleep 5
done

# Run the cleanUp method to remove cruft.
cleanUp
