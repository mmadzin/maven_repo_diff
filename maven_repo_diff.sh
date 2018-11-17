#!/bin/bash

DIFFERS=()
NOT_FOUND=()
CHECKED=()
ADDITIONAL_FOUND=()

while getopts a:b:d:w: option
do
case "${option}"
in
a) A_ZIP=${OPTARG};;
b) B_ZIP=${OPTARG};;
d) DIST_DIFF=${OPTARG};;
w) WORKSPACE=${OPTARG};;
esac
done

DIST_DIFF="${DIST_DIFF:-dist-diff2-0.9.1-jar-with-dependencies.jar}"
WORKSPACE="${WORKSPACE:-/tmp/maven_repo_diff}"

if [ "$A_ZIP" == "" ] || [ "$B_ZIP" == "" ]; then
  echo "Usage:"
  echo "     sh maven_repo_diff.sh -a <a.zip> -b <b.zip> [-d <dist_diff>] [-w <workspace_dir>]"
  exit 1
fi

is_dist_diff_relevant () {
  relevant_changes=0
  
  relevant_changes=$(($relevant_changes + $(cat $1 | grep -c "Added methods:") ))
  relevant_changes=$(($relevant_changes + $(cat $1 | grep -c "Added fields:") ))
  relevant_changes=$(($relevant_changes + $(cat $1 | grep -c "Field modifiers changes:") ))
  relevant_changes=$(($relevant_changes + $(cat $1 | grep -c "Decompiled source diff:") ))
  
  if [[ $relevant_changes > 0 ]]; then
    return 0
  else 
    return 1
  fi
}

A_MAVEN_REPO_NAME=`unzip -l $A_ZIP | sed -n 's/.*\(jws-.*-maven-repository\)\/$/\1/p'`
B_MAVEN_REPO_NAME=`unzip -l $B_ZIP | sed -n 's/.*\(jws-.*-maven-repository\)\/$/\1/p'`

mkdir -p $WORKSPACE
rm -rf $WORKSPACE/folderA $WORKSPACE/folderB $WORKSPACE/a $WORKSPACE/b 
rm -rf $WORKSPACE/TEST-report.xml $WORKSPACE/DIFFERENCE_*

mkdir $WORKSPACE/a $WORKSPACE/b

# Unzip packages into WORKSPACE
unzip -qq $A_ZIP -d $WORKSPACE/a
unzip -qq $B_ZIP -d $WORKSPACE/b

a_dir=$WORKSPACE"/folderA"
b_dir=$WORKSPACE"/folderB"

mkdir $a_dir $b_dir

# Goes through <A_dir> and looks for jar files
for path in $(find $WORKSPACE/a -name "*.jar"); do
  jar=$(basename $path)
  service_pack_jar=""

  # Because redhat number can differ among versions, it's necessary to remove it
  if [[ $jar = *"redhat-"* ]]; then
    jar=${jar%%redhat-*}
    ending=${path##*redhat-}
    ending=`echo $ending | sed -r 's/^[0-9]+//g'`
  fi
 
  # Finds equivalent file in <B_dir> and ensures that found file differs only in number 
  # behind 'redhat-' substring
  for opt in $(find $WORKSPACE/b -name "$jar*$ending"); do 
    opt_jar=$(basename $opt)

    if [[ $opt_jar = *"redhat-"* ]]; then
      opt_ending=${opt_jar##*redhat-}
      opt_ending=`echo $opt_ending | sed -r 's/^[0-9]+//g'`
      
      if [[ "$opt_ending" = "$ending" ]]; then
        service_pack_jar=$opt
      fi
    else
      service_pack_jar=$opt
    fi
  done

  if [ "$service_pack_jar" == "" ]; then
     NOT_FOUND+=($(basename $path))
     continue
  fi

  # Store that the file was checked
  CHECKED+=($(basename $service_pack_jar))

  # Compare md5sums
  a_sum=`md5sum $path | awk '{ print $1 }'`
  b_sum=`md5sum $service_pack_jar | awk '{ print $1 }'`

  if [ "$a_sum" == "$b_sum" ]; then
     continue
  fi  

  # Checks different files and looks for differences in classes
  # Unzip
  rm -rf $a_dir/* $b_dir/*

  jar=$(basename $path)

  cp $path $a_dir 
  cp $service_pack_jar $b_dir/$jar

  # Dist diff
  output_dir=$WORKSPACE/"dist_diff_output"
  cp $DIST_DIFF $WORKSPACE

  diff_jar=`java -jar $WORKSPACE/$(basename $DIST_DIFF) -a $a_dir -b $b_dir -o $output_dir -d | grep "DIFFERENT"`
  
  if [[ "$diff_jar" != "" ]]; then 
    if is_dist_diff_relevant $output_dir"/dist-diff2-output.html"; then
      DIFFERS+=($(basename $path))
      cp $output_dir"/dist-diff2-output.html" $WORKSPACE"/DIFFERENCE_"`basename $path`".html"
    fi
  fi
done 

# Goes through <B_dir> and looks for jar files
for path in $(find $WORKSPACE/b -name "*.jar"); do
  jar=$(basename $path)
  found=0

  for checked in "${CHECKED[@]}"; do
    if [[ "$jar" == "$checked" ]]; then
      found=1
      break
    fi
  done

  if [[ "$found" == "0" ]]; then
     ADDITIONAL_FOUND+=($(basename $path))
  fi
done

echo
echo Different:
printf "\t%s\n"  "${DIFFERS[@]}"

echo
echo Not Found in `basename $B_ZIP`:
printf "\t%s\n"  "${NOT_FOUND[@]}"

echo
echo Additional Files in `basename $B_ZIP`:
printf "\t%s\n"  "${ADDITIONAL_FOUND[@]}"

# Clean up the WORKSPACE directory 
rm -rf $WORKSPACE/folderA $WORKSPACE/folderB $WORKSPACE/a $WORKSPACE/b $WORKSPACE/output

# Prepare report
failures=0
f=$WORKSPACE/TEST-report.xml

if [[ ${#DIFFERS[@]} > 0 ]]; then
  failures=$(($failures + 1))
fi

if [[ ${#NOT_FOUND[@]} > 0 ]]; then
  failures=$(($failures + 1))
fi

if [[ ${#ADDITIONAL_FOUND[@]} > 0 ]]; then
  failures=$(($failures + 1))
fi

echo '<testsuite name="Maven diff" time="0" tests="3" errors="0" skipped="0" failures="'$failures'">' > $f
echo '  <testcase name="Different Packages" time="0">' >> $f

if [[ ${#DIFFERS[@]} > 0 ]]; then
  echo '    <failure message="Archives differ in some packages">' >> $f
  for diff in "${!DIFFERS[@]}"; do
    echo '      '"${DIFFERS[$diff]}" >> $f
  done
  echo '    </failure>' >> $f
fi

echo '  </testcase>' >> $f
echo '  <testcase name="Missing Packages" time="0">' >> $f

if [[ ${#NOT_FOUND[@]} > 0 ]]; then
  echo '    <failure message="Not Found in '`basename $B_ZIP`'">' >> $f
  for not in "${!NOT_FOUND[@]}"; do
    echo '      '"${NOT_FOUND[$not]}" >> $f
  done
  echo '    </failure>' >> $f
fi

echo '  </testcase>' >> $f
echo '  <testcase name="Additional Packages" time="0">' >> $f

if [[ ${#ADDITIONAL_FOUND[@]} > 0 ]]; then
  echo '    <failure message="Additional Files in '`basename $B_ZIP`'">' >> $f
  for not in "${!ADDITIONAL_FOUND[@]}"; do
    echo '      '"${ADDITIONAL_FOUND[$not]}" >> $f
  done
  echo '    </failure>' >> $f
fi

echo '  </testcase>' >> $f
echo '</testsuite>' >> $f

echo
echo Report stored to $f
