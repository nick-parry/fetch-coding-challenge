#!/bin/bash
################################################################################
# A scratch pad to try and work out the logging/output only using a 
# pre-populated data directory.
# Not used in the happy path. But, kept to show how I was troubleshooting some stuff.
# NP 09-24-24
################################################################################

# Find the unique domains from the filenames of data we have
uniqueDomains="$(cat data/checks/* | jq -r .domain | sort -u)"

for domain in $uniqueDomains;do
    # Now find out how many requests we have made so far for this domain
    upCount="$(cat data/checks/* | jq "select(.domain == \"$domain\") | select(.status == \"up\")" -c | wc -l)"
    tryCount="$(cat data/checks/* | jq "select(.domain == \"$domain\")" -c | wc -l)"
    availability="$(printf "%.0f\n" $(echo "100 * ($upCount / $tryCount)" | bc -l | bc))"
    echo "$domain has ${availability}% availability percentage"
done

