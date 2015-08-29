#!/usr/bin/env python

# Add a project to GPROG_DIR

import sys
import subprocess
import logging
import os

from colorama import Fore

try:
    from rainbow_logging_handler import RainbowLoggingHandler
except:
    print >>sys.stderr, "pip install rainbow_logging_handler"
    sys.exit(1)

def main(repository_url):
    """
    Check out git project from repository_url
    """
    logger.debug("checking out %s" % repository_url)
    basename = os.path.basename(repository_url)
    logger.debug("basename: %s" % basename)
    if basename.endswith('.git'):
        basename = basename[:-len('.git')]
    logger.debug("directory name will be %s" % (basename))
    output_dirname = os.path.join(os.environ["HOME"], 'gprog', basename)
    if os.path.exists(output_dirname):
        logger.error("You've already checked out %s" % repository_url)
        logger.error("cd %s && git pull" % (output_dirname))
    else:
        logger.info("Checking out %s" % (repository_url))
        try:
            subprocess.check_call(['git', 'clone', repository_url],
                                  cwd=os.path.dirname(output_dirname))
        except Exception,e:
            logger.error("Failed to checkout %s" % (repository_url))
            raise(e)

def usage():
    print >>sys.stderr, "Usage:", os.path.basename(sys.argv[0]), "project_url"
    sys.exit(1)
    
if __name__ == "__main__":
    logger = logging.getLogger('logging')
    logger.setLevel(logging.DEBUG)
    handler = RainbowLoggingHandler(sys.stderr)
    logger.addHandler(handler)
    if len(sys.argv) != 2:
        usage()
    main(sys.argv[1])
