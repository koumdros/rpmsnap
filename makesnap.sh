#!/bin/bash

# ==================================================================================
# Script to run "rpmsnap.pl", presumably from crontab
#
# In root's crontab, one may have for example:
#
# 00 17 */3 * * $DIR/rpm/sbin/makesnap.sh 2>/dev/null
#
# Underneath "DIR", things should presumable look like this:
# .
# ├── bin
# │   └── rpmsnapcmp.pl
# ├── data
# │   └── yourhost.yourdomain.yourtld
# │       ├── rpmsnap.2013-01-07_17:00:01.txt
# │       ├── rpmsnap.2013-03-04_17:00:02.txt
# │       ├── rpmsnap.2013-04-07_17:00:01.txt
# │       └── rpmsnap.2013-06-07_17:00:01.txt
# └── sbin
#     ├── getHostname_function.sh
#     ├── makesnap.sh
#     ├── prelinkfix.sh
#     └── rpmsnap.pl
#
# ==================================================================================

set -o nounset

# Set the installation directory; ** change this as desired **

DIR=/usr/local/toolbox/rpmsnap

# Used in creating the suffix of files written to DATADIR

NOW=`date +%Y-%m-%d_%H:%M:%S`

# Source a function to determine the hostname

F1=$DIR/sbin/getHostname_function.sh
source $F1
if [[ $? != 0 ]]; then
   echo "Could not source the getHostname() function from '$F1' -- exiting" >&2
   exit 1
fi

# Perl script that creates the list of packages

RPMSNAP=$DIR/sbin/rpmsnap.pl
if [[ ! -x $RPMSNAP ]]; then
   echo "Script '$RPMSNAP' not found or not executable -- exiting" >&2
   exit 1
fi

# Determine the hostname; the shell should provide its own HOSTNAME value and one
# should use that; here we are overly cautious

MYHOSTNAME=$(getHostname)
echo "Hostname determined to be '$MYHOSTNAME'" >&2

# Result files of "rpmsnap.pl" go into the DATADIR, which depends on the MYHOSTNAME

DATADIR=$DIR/data/$MYHOSTNAME  

# ----
# Special hack because there is a machine with the same hostname but which uses different OS
# depending on time of week (here only for several Fedora releases)
# ----

DOUBLE_PERSONALITY_HOST=some.random.host.org

function makeFedoraSuffix {
   # https://fedoraproject.org/wiki/History_of_Fedora_release_names
   grep --quiet "Heisenbug" /etc/issue
   if [[ $? -eq 0  ]]; then
      echo ".f20"
      return
   fi
   grep --quiet "Schrödinger’s Cat" /etc/issue
   if [[ $? -eq 0  ]]; then
      echo ".f19"
      return
   fi
   grep --quiet "Spherical Cow" /etc/issue
   if [[ $? -eq 0  ]]; then
      echo ".f18"
      return
   fi
   grep --quiet "Beefy Miracle" /etc/issue
   if [[ $? -eq 0  ]]; then
      echo ".f17"
      return
   fi
   # else no suffix
}

if [[ $DOUBLE_PERSONALITY_HOST == $MYHOSTNAME ]]; then
   SUFFIX=`makeFedoraSuffix`
   DATADIR="${DATADIR}${SUFFIX}"
fi

echo "Target directory is '$DATADIR'" >&2

# ----
# Function to decide what to do with a new file
# ----

function keepOrDelete {
   local LATEST=$1
   local FILE_NEW=$2
   local FILE_FINAL=$3
   if [[ -n $LATEST ]]; then
      diff "$FILE_NEW" "$LATEST" > /dev/null
      local RETVAL=$?
      case $RETVAL in
         0)
            echo "No differences found between '$FILE_NEW' and '$LATEST' -- deleting '$FILE_NEW'" >&2
            /bin/rm "$FILE_NEW"      
         ;;
         1)
            echo "Differences found between '$FILE_NEW' and '$LATEST' -- keeping '$FILE_NEW'" >&2
            /bin/mv "$FILE_NEW" "$FILE_FINAL"
         ;;
         2)
            echo "Some problem occurred with 'diff' (parameters were: '$FILE_NEW' '$LATEST') -- exiting" >&2
            exit 1
         ;;
         *)
            echo "Unexpected returnvalue $RETVAL from 'diff' -- exiting" >&2
            exit 1
         ;;
      esac
   else 
      # No latest - just keep current
      /bin/mv "$FILE_NEW" "$FILE_FINAL"
   fi
}

# ----
# Create the DATADIR into which files are saved if needed.
# ----

if [[ ! -d "$DATADIR" ]]; then
   echo "Directory '$DATADIR' does not exist - creating it" >&2 
   mkdir "$DATADIR"
   if [[ $? != 0 ]]; then
      echo "Could not create directory '$DATADIR' -- exiting" >&2
      exit 1
   fi
fi

# ----
# Run "rpmsnap.pl"
#
# The STDOUT is captured in the OUTFILE_NEW; later we will decide whether we will keep it; if there
# are no changes relative to an earlier file, there is no reason to do so.
#
# The STDERR is cpatured in the ERRFILE_NEW; later we will decide whether we will keep it; if there
# are no changes relative to an earlier file, there is no reason to do so.
#
# The ERRFILE_NEW lists "prelink" errors, which can be solved using the following pipe:
# cat $ERRFILE | perl -n -e 'if (~/prelink: (\S+):/) { print "$1\n" }' | sort --unique | xargs prelink
# ----

OUTFILE="${DATADIR}/rpmsnap.${NOW}.txt"
OUTFILE_NEW="${OUTFILE}.new"

ERRFILE="${DATADIR}/rpmsnap.${NOW}.err"
ERRFILE_NEW="${ERRFILE}.new"

echo "'rpmsnap' information goes to '$OUTFILE_NEW'" >&2
echo "'rpmsnap' errors go to '$ERRFILE_NEW'" >&2

"$RPMSNAP" --verify >"$OUTFILE_NEW" 2>"$ERRFILE_NEW"

if [[ $? -ne 0 ]]; then
   echo "Problem running '$RPMSNAP' -- exiting." >&2
   echo "Errors may be in '$ERRFILE_NEW'" >&2
   exit 1
fi

# ----
# Compare contents of $OUTFILE_NEW with the latest $OUTFILE created.
# The latest $OUTFILE is simply obtained by lexicographical sorting of the contents of $DATADIR
# Note that LATEST_(OUT|ERR) may not exist yet!
# ----

LATEST_OUT=`ls "$DATADIR"/rpmsnap.*.txt 2>/dev/null | sort | tail -1`

keepOrDelete "$LATEST_OUT" "$OUTFILE_NEW" "$OUTFILE"

LATEST_ERR=`ls "$DATADIR"/rpmsnap.*.err 2>/dev/null | sort | tail -1`

keepOrDelete "$LATEST_ERR" "$ERRFILE_NEW" "$ERRFILE"


