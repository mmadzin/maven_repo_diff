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

A_MAVEN_REPO_NAME=`unzip -l $A_ZIP | sed -n 's/.*\(jboss-web-server-.*-maven-repository\)\/$/\1/p'`
B_MAVEN_REPO_NAME=`unzip -l $B_ZIP | sed -n 's/.*\(jboss-web-server-.*-maven-repository\)\/$/\1/p'`

mkdir -p $WORKSPACE
rm -rf $WORKSPACE/*

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
  cp $DIST_DIFF $WORKSPACE
  diff_jar=`java -jar $WORKSPACE/$(basename $DIST_DIFF) -a $a_dir -b $b_dir -d | grep "DIFFERENT"`
  
  if [[ "$diff_jar" != "" ]]; then 
    DIFFERS+=($(basename $path))
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
echo Additional files in `basename $B_ZIP`:
printf "\t%s\n"  "${ADDITIONAL_FOUND[@]}"

# Clean up the WORKSPACE directory 
rm -rf $WORKSPACE/*
