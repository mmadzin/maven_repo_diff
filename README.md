Maven repo diff script is looking for differences in jar files between two maven repositories. The script uses dist_diff comparator (tested with 0.9.1) which can't be used directly on maven repositories in case repositories contain different versions.

Usage:
  sh maven_repo_diff.sh -a <a.zip> -b <b.zip> [-d <dist_diff>] [-w <workspace_dir>]

Dist_diff repository: https://repository.engineering.redhat.com/nexus/content/repositories/jboss-qa-releases/org/jboss/qa/dist-diff2 

