Maven repo diff script is looking for differences in jar files between two maven repositories. The script uses dist_diff comparator (tested with 0.9.1) which can't be used directly on maven repositories in case repositories contain different versions.

Usage:
  sh jar_diff.sh -a <A.zip> -b <B.zip> [-d <DIST_DIFF>] [-w <WORKSPACE>]

Dist_diff repository: https://repository.engineering.redhat.com/nexus/content/repositories/jboss-qa-releases/org/jboss/qa/dist-diff2 

