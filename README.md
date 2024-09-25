# Fetch Coding Interview Challenge

Prepared for the first interaction/coding interview for Fetch on 9-24-24.

## Overview
This is based on a request from the hiring manager/technical recruiter and my first interaction after an application at
Fetch.

The problem statement can be found here in ./health-check.pdf. And can be found on the internet at large here:
https://fetch-hiring.s3.us-east-1.amazonaws.com/site-reliability-engineer/health-check.pdf

## Bash? Really?
Yes. Bash. :) I don't really love coding interviews in general. But, I felt like trying to make it fun today. I could
have chosen Python or Golang, but for pure speed of hackery(and a challenge) I chose bash.

## When would this not be Bash?
If this was a real problem that we needed to solve where we would want to maintain and add features over time.
Especially if my team doesn't love bash. Another reason to "scale it up to something else" would be if there were
more, or more complicated, http checks. Using the example input file(./input.yaml), it was easy enough to 
manage with bash. But as you scale up the quality of the problem, Bash becomes less and less appealing.

## Walkthrough
I tried to comment what my reasoning was throughout the script. I would be happy to answer any questions and/or learn
about how I could be more clear in my code/comments. 

## Example usage
I wrote this on my Ubuntu 22 machine. I have been using Ubuntu as my workstation/only OS for 14 years or so now. 
I didn't add any OS checks, so I am not 100% sure it will work on Mac. Specifically, I am not sure about how I am using
`sed` and `date` and if that will play nice on a BSD based system? Sorry. 

Here is the output of me running it. 
```
$ ./healthCheck.sh input.yaml 
fetch.com has 67% availability percentage
www.fetchrewards.com has 0% availability percentage
fetch.com has 67% availability percentage
www.fetchrewards.com has 0% availability percentage
fetch.com has 60% availability percentage
www.fetchrewards.com has 0% availability percentage
fetch.com has 67% availability percentage
www.fetchrewards.com has 0% availability percentage
^C
```