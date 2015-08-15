#!/usr/bin/env python
import os
import sys
import textwrap
import subprocess
from colorama import Fore, Style

TEXT="""
                ___________ 
               |        |. |
              (| (=)    |. |
               |________|. |
       (___)   +-----------|
         ||  ,<|  o  |___| |
         || /  |  o     || |
          "    |  o    //  |
               +i^i--(--)--+
               | |      | |
               | |      | |
             l===l    l===l
"""

def say(text):
    (height, width) = [int(x) for x in os.popen('stty size', 'r').read().split()]
    max_line_width = max([len(line) for line in TEXT.split("\n")])
    width = min(width, 80)
    start_text_index = 2
    ret = ""
    lines = TEXT.split("\n")
    rest_width = width - max_line_width
    # print (width, max_line_width, rest_width)
    text_lines = textwrap.wrap(text, rest_width)
    appended_text_lines = ['', '', '-' * rest_width] + text_lines + ['-' * rest_width]
    if len(appended_text_lines) < len(lines):
        appended_text_lines = appended_text_lines + [''] * (len(lines) - len(appended_text_lines))
    elif len(lines) < len(appended_text_lines):
        lines = lines + [''] * (len(appended_text_lines) - len(lines))
    text_lines_num = len(text_lines)
    for line, i, t in zip(lines, range(len(lines)), appended_text_lines):
        print line.ljust(max_line_width),
        print Fore.CYAN + t + Fore.RESET
        ret = ret + line.ljust(max_line_width) + t + "\n"
    return ret
ret = say(" ".join(sys.argv[1:]))

