#!/usr/bin/env python3

#
# 1. This script reads a tab-separated list of documents, only containing two fields: the content of the document encoded with base64 and the URL
# 2. It decompress the base64 field and uses libmagic to identify the MIME type and character encoding
# 3. The output produced is:
#    character_encoding     MIME    URL    content_base64
#

import sys
import hashlib
import base64
import argparse


oparser = argparse.ArgumentParser(description="Script that takes the output of bitextor-crawl2ett and removes duplicate files.")
oparser.add_argument('ett', metavar='ETT', nargs='?', help='Output of the bitextor-crawl2ett script (in format ETT).', default=None)
oparser.add_argument('--root-dir', dest='rootDir', help='Domain directory')

options = oparser.parse_args()

if options.ett == None:
  reader = sys.stdin
else:
  reader = open(options.ett,"r")

outFile = open("{rootDir}/deduped".format(rootDir=options.rootDir), "wt")

lineNum = 0
seen_md5={}
for i in reader:
  fields = i.strip().split("\t")
  try:
    deboiledFile = open("{rootDir}/deboiled/{name}".format(rootDir=options.rootDir, name=lineNum), "r")
    e = deboiledFile.read()
    deboiledFile.close()
    e = base64.b64encode(e.encode()).decode()

    #e = fields[3]
    #We compute MD5 signature to compare files and detect duplicates
    c = hashlib.md5()
    c.update(e.encode("utf8"))
    sys.stderr.write(c.hexdigest() + "\n")

    #checking for duplicate content (duplicates are discarded)
    if c.hexdigest() in seen_md5:
      pass
      #sys.stderr.write("Repeated file:\t"+fields[2]+"\tfirst occurrence\t"+seen_md5[c.hexdigest()]+"\n")
    else:
      outFile.write(str(lineNum) + "\n")

      seen_md5[c.hexdigest()]=fields[2]
      print("{0}\t{1}\t{2}\t{3}\t{4}".format(fields[0].strip(),fields[1],fields[2],e, lineNum))
  except UnicodeDecodeError:
    #sys.stderr.write("File "+fields[2]+" produced a character encoding error")
    pass

  lineNum += 1

outFile.close()
