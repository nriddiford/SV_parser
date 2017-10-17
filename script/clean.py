#!/usr/bin/env python

import sys
import os

from optparse import OptionParser

parser = OptionParser()

parser.add_option("-f",
    "--in_file",
    dest="in_file",
    help="Clustered and annotated SV calls produced by svClusters/sv2gene")

options, args = parser.parse_args()

if not options.in_file:
    parser.error('No input file provided')

base_name = (os.path.splitext(options.in_file)[0])
out_base = base_name.split('_')[0]
outfile = out_base + "_" + "cleaned_SVs.txt"

false_calls_file = 'all_samples_false_calls.txt'

# def index_exists(ls, i):
#     return (0 <= i < len(ls)) or (-len(ls) <= i < 0)

def remove_false_positives(false_calls_file, input_file, clean_output):
    """Remove entries in input_file if the 20th column equals F"""
    i = 1
    filtered_calls = 0
    with open(false_calls_file, 'a+') as false_calls, open(input_file,'U') as infile, open(clean_output, 'w') as clean_files:
        false_calls.seek(0)
        seen_lines = {line.rstrip() for line in false_calls}
        written_header = False
        for l in infile:
            parts = l.rstrip().split('\t')

            if i == 1 and parts[0] == 'event':
                header = l
                continue

            match = "%s_" % out_base + "_".join(parts[3:7])

            try:
                notes = parts[20]
            except IndexError:
                notes = '-'

            if notes == 'F':
                filtered_calls += 1
                if not match in seen_lines:
                    false_calls.write("%s\n" % (match))

            elif match in seen_lines:
                filtered_calls += 1

            elif notes != 'F':
                if not written_header:  # do this only once
                    clean_files.write(header)
                    written_header = True
                clean_files.write(l)
            i += 1
    if filtered_calls:
        print "Removed %s false positives from %s" % (filtered_calls, input_file)

remove_false_positives(false_calls_file=false_calls_file, input_file=options.in_file, clean_output=outfile)
