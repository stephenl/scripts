function jenkins-curl {
  local JENKINS_AUTH="$(cat ~/.jenkins-user):$(awk -v url=$JENKINS_URL '$1 == url {print $2}' ~/.jenkins-token)"
  curl -s -u "$JENKINS_AUTH" "$@"
}

# This is meant to be called
# from ~/.profile or ~/.bash_aliases
# to setup the environment variables
# necessary to run other jenkins
# functions
function setup-jenkins {
  export JENKINS_URL=$1
  export JENKINS_DEFAULT_VIEW=$2
}

function ci {
  open "$JENKINS_URL/view/$(git-tracking | sed s:/:_:)"
}

function jenkins-views {
  #jenkins-curl -g $JENKINS_URL/api/xml?tree=views[name] | xpath "/hudson/view/name" 2>&1 | grep -F "<name>" | sed -E "s:<name>(.*)</name>(-- NODE --)?:\1:"
  echo "<root>$(jenkins-curl -g $JENKINS_URL/api/xml?tree=views[name])</root>" | xpath "/root/hudson/view/name" 2>&1 | grep -F "<name>" | sed -E "s:<name>(.*)</name>(-- NODE --)?:\1:"
}

function jenkins-job-last {
  job=$1
  last=$2
  jenkins-curl $JENKINS_URL/job/$job/api/xml?xpath=//$last/number | xml-element-value
}
function jenkins-job-lastBuild {
  jenkins-job-last $1 lastBuild
}
function jenkins-job-lastStableBuild {
  jenkins-job-last $1 lastStableBuild
}
function jenkins-job-lastCompletedBuild {
  jenkins-job-last $1 lastCompletedBuild
}
function jenkins-job-lastSuccessfulBuild {
  jenkins-job-last $1 lastSuccessfulBuild
}
function jenkins-job-lastUnstableBuild {
  jenkins-job-last $1 lastUnstableBuild
}
function jenkins-job-lastUnsuccessfulBuild {
  jenkins-job-last $1 lastUnsuccessfulBuild
}
function jenkins-job-description {
  jenkins-curl $JENKINS_URL/job/$1/description
}

function jenkins-rss-failed-default {
  jenkins-rss-failed $JENKINS_URL/view/$JENKINS_DEFAULT_VIEW
}

function jenkins-rss-all-default {
  jenkins-rss-all $JENKINS_URL/view/$JENKINS_DEFAULT_VIEW
}

function jenkins-rss-latest-default {
  jenkins-rss-latest $JENKINS_URL/view/$JENKINS_DEFAULT_VIEW
}

function xml-element-value {
  grep -o '[">].*["<]' | sed -E 's/[">](.*)["<]/\1/'
}

function jenkins-xpath-date-link-title {
  xpath "/feed/entry/updated|/feed/entry/link/@href|/feed/entry/title" 2>&1 \
  | xml-element-value | awk '{t=$0 " " t} NR%3==0 {print t; t=""}'
}

function jenkins-xpath-date-link {
  xpath "/feed/entry/updated|/feed/entry/link/@href" 2>&1 \
  | xml-element-value | xargs -n 2 | awk '{printf("%s %s\n", $2, $1)}'
}

function jenkins-job-result {
  job=$1
  jenkins-curl $job/api/xml?xpath=//result | xml-element-value
}

function jenkins-rss-failed {
  if [ -z $1 ]; then
    url=$JENKINS_URL/rssFailed
  else
    url=$1/rssFailed
  fi
  jenkins-curl $url | jenkins-xpath-date-link
}

function jenkins-rss-all {
  if [ -z $1 ]; then
    url=$JENKINS_URL/rssAll
  else
    url=$1/rssAll
  fi
  jenkins-curl $url | jenkins-xpath-date-link
}

function jenkins-rss-latest {
  if [ -z $1 ]; then
    url=$JENKINS_URL/rssLatest
  else
    url=$1/rssLatest
  fi
  jenkins-curl $url | jenkins-xpath-date-link
}

function jenkins-console {
  jenkins-curl $1/consoleText
}

function jenkins-console-failed {
  jenkins-console $1 | grep -E -e "T[Ee][Ss][Tt].*FAILED" -e "FAILURE"
}

function jenkins-console-crashed {
  jenkins-console $1 | grep "Tests FAILED (crashed)"
}

function jenkins-console-timeout {
  jenkins-console $1 | grep "junit.framework.AssertionFailedError: Timeout occurred. Please note the time in the report does not reflect the time until the timeout."
}

function jenkins-console-testsuites {
  jenkins-console $1 | awk '/Testsuite/ {suite = suite $3} /Tests run/ {print suite " " $13; suite=""}'
}

function jenkins-console-testcases {
  jenkins-console $1 | awk '/Testsuite/ {suite=$3} /Testcase/ {print suite "." $3 " " $5}'
}

function jenkins-top-list {
  jenkins-views | cut -d _ -f 1 | uniq -c | sort -nr
}

function jenkins-top-list-merged {
  jenkins-views | sed "s:_:/:" \
  | while read i; do 
    git show-ref -q $i && git merge-base --is-ancestor $i $MASTER && echo $i
  done | cut -d / -f 1 | uniq -c | sort -nr
}

function jenkins-label-tiedJobs {
  label=$1
  jenkins-curl "$JENKINS_URL/label/$label/api/xml" | xpath "/labelAtom/tiedJob/name" 2>&1 | grep -F "<name>" | sed -E "s:<name>(.*)</name>(-- NODE --)?:\1:"
}

function jenkins-jobs {
  view=$1
  jenkins-curl "$JENKINS_URL/view/$view/api/xml" | xpath "/listView/job/name" 2>&1 | grep -F "<name>" | sed -E "s:<name>(.*)</name>(-- NODE --)?:\1:"
}

function jenkins-build {
  job=$1
  jenkins-curl -X POST "$JENKINS_URL/job/$job/build"
}

function jenkins-stop {
  job=$1
  jenkins-curl -X POST "$JENKINS_URL/job/$job/lastBuild/stop"
}

function jenkins-stop-view {
  view=$1
  jenkins-jobs $view | while read i; do
    jenkins-stop $i
  done
}

function jenkins-job-disable {
  job=$1
  jenkins-curl -X POST "$JENKINS_URL/job/$job/disable"
}

function jenkins-job-enable {
  job=$1
  jenkins-curl -X POST "$JENKINS_URL/job/$job/enable"
}

function jenkins-delete-slave {
  slave=$1
  jenkins-curl -X POST "$JENKINS_URL/computer/$slave/doDelete"
}

function jenkins-delete-job {
  job=$1
  jenkins-curl -X POST "$JENKINS_URL/job/$job/doDelete"
}

function jenkins-delete-view {
  view=$1
  jenkins-curl -X POST "$JENKINS_URL/view/$view/doDelete"
}

function jenkins-delete-view-and-jobs {
  view=$1
  jenkins-jobs $view | while read i; do jenkins-delete-job $i; done && jenkins-delete-view $view
}

function time-diff {
  awk '{
    cmd=sprintf("date -j -f %%H:%%M:%%S %s +%%s", $1); cmd | getline; close(cmd)
    if (b == 0) {
      start=$0; b=1
    } else {
      diff=$0-start + (start > $0 ? 86400 : 0); b=0
      printf("%.2i:%.2i\n", int(diff/60), diff%60)
    }
  }'
}

function jenkins-framework-duration {
  grep -E "Framework .+ (started|finished)" | awk '{
    cmd=sprintf("date -j -f %%H:%%M:%%S %s +%%s", $5); cmd | getline; close(cmd)
    if (b == 0) {
      start=$0; b=1
    } else {
      diff=$0-start + (start > $0 ? 86400 : 0); b=0
      printf("%.2i:%.2i\n", int(diff/60), diff%60)
    }
  }'
}

function jenkins-job-duration {
  jenkins-curl "$i/api/xml?xpath=//duration" | xml-element-value
}

function jenkins-jboss-duration {
  grep -E "Starting Jboss|Jboss Started" | awk '{
    cmd=sprintf("date -j -f %%H:%%M:%%S %s +%%s", $4); cmd | getline; close(cmd)
    if (b == 0) {
      start=$0; b=1
    } else {
      diff=$0-start + (start > $0 ? 86400 : 0); b=0
      printf("%.2i:%.2i\n", int(diff/60), diff%60)
    }
  }'
}

# Takes the output of consoleText of a job that
# runs JUnit tests and greps for given test suites
# Then it keeps track of how long the test suite
# took to run
function jenkins-testsuite-times {
  testsuite=$1
  grep -A 1 "Testsuite: $testsuite" | awk '
    /Testsuite/ { suite=$3 }
    /Tests run/ { times[suite]=times[suite] " " $13 }
    END { for(key in times) print key times[key] }' | sed 's/,//'
}

function jenkins-testpackage-times {
  jenkins-testsuite-times | awk '
    {
      delete a[split("." $1,a,".")]
      b=""; for(i in a) b=b a[i] "."; b=substr(b,1,length(b)-2)
      t[b]+=$2
    }
    END {for(i in t) printf("%.3f %s\n",t[i], i)}
  ' | sort -n
}

function jenkins-testsuite-stats {
  testsuite=$1
  grep -A 1 "Testsuite: $testsuite" | awk '
    BEGIN { print "suite,avg,stddev,min,max,count" }
    /Testsuite/ { suite=$3 }
    /Tests run/ {
      data=$13
      count[suite]++; sum[suite]+=data; sqrsum[suite]+=data*data
      if (min[suite] == "") {
        min[suite] = data
        max[suite] = data
      } else {
        if (min[suite] > data) {
          min[suite] = data
        }
        if (max[suite] < data) {
          max[suite] = data
        }
      }
    }
    END {
      for(key in count) {
        avg=sum[key]/count[key]
        stddev=sqrt(sqrsum[key]/count[key] - avg*avg)
        printf("%s,%f,%f,%f,%f,%i\n", key, avg, stddev, min[key], max[key], count[key])
      }
    }'
}

function jenkins-script {
  script=$1
  url=${2-$JENKINS_URL}
  jenkins-curl -H 'Expect:' --data-urlencode "script=$(cat $script)" $url/scriptText
}

# when Jenkins master runs out of disk space
# the slaves die, so this finds all slaves
# and restarts the thread to bring them
# back up
function jenkins-yank {
  jenkins-curl $JENKINS_URL \
  | grep -o -E "[a-z0-9/-]*causeOfDeath" \
  | sed 's/causeOfDeath/yank/' \
  | while read i; do \
    jenkins-curl -X POST $JENKINS_URL/$i
  done
}

# find slaves with no executors
# need to match against the list
# of active ec2 instances, if
# the instance has been terminated,
# then it's fine to run jenkins-delete-slave
function jenkins-dead-slaves {
  jenkins-curl "$JENKINS_URL/computer/api/xml?xpath=/computerSet/computer\[numExecutors=0\]/displayName&wrapper=displayName" \
  | sed 's:</displayName>: :g;s:<displayName>::g' \
  | tr ' ' '\n'
}
