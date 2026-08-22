#!/usr/bin/env python
"""
Get the latest timestamp of directories.
"""

import os
from argparse import ArgumentParser


def main(root_directory):
    latest_modified_at = None
    IGNORE_DIRECTORIES = ['.git', '.ccls-cache']
    for root, dirs, _files in os.walk(root_directory):
        for d in dirs:
            if d in IGNORE_DIRECTORIES:
                continue
            full_path = os.path.join(root, d)
            modified_at = os.stat(full_path).st_mtime  # seconds from epoch in float
            if not latest_modified_at:
                latest_modified_at = modified_at
            elif modified_at > latest_modified_at:
                latest_modified_at = modified_at
    print(latest_modified_at)

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('root')
    args = parser.parse_args()
    main(args.root)
