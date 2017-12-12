import sys
import gzip
import os
import logging
import argparse
import re
import operator
from Bio import SeqIO
from Bio.Seq import Seq
from CountXmlUtils import readCountXmlFeatures
from Feature import FeatureItem, FeatureGroup
from audioop import reverse

DEBUG = 1

if DEBUG:
  #inputFile="/scratch/cqs/shengq2/vickers/20170628_smallRNA_3018-KCV-77_78_79_mouse_v3/temp/temp.list"
  inputFile = "/scratch/cqs/shengq2/vickers/20170628_smallRNA_3018-KCV-77_78_79_mouse_v3/temp/smallRNA_1mm_KCV_3018_77_78_79.filelist"
  outputFile = "/scratch/cqs/shengq2/vickers/20170628_smallRNA_3018-KCV-77_78_79_mouse_v3/temp/temp.endpoint.txt"
else:
  parser = argparse.ArgumentParser(description="Generate smallRNA NTA read for Fastq file.",
                                   formatter_class=argparse.ArgumentDefaultsHelpFormatter)

  parser.add_argument('-i', '--input', action='store', nargs='?', help='Input xml file list')
  parser.add_argument('-o', '--output', action='store', nargs='?', help="Output endpoint file")

  args = parser.parse_args()
  
  print(args)
  
  inputFile = args.input
  outputFile = args.output

logger = logging.getLogger('smallRNAEndPosition')
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)-8s - %(message)s')

with open(inputFile, "r") as ir:
  files = [line.rstrip().split('\t') for line in ir]

fileFeatures = []
for file in files:
  logger.info("Reading feature-query in %s ..." % file[1])
  fileFeatures.append([file[0], readCountXmlFeatures(file[1])])

groupNames = set()
for features in fileFeatures:
  for mf in features[1]:
    for f in mf.Features:
      groupNames.add(f.Name.split(':')[0])
groupNames = sorted(groupNames)

groupFeatureMap = {}
for gname in groupNames:
  gmap = {};
  groupFeatureMap[gname] = gmap
  for features in fileFeatures:
    mappedFeatures = features[1]
    gFeatures = [fg for fg in mappedFeatures if fg.Features[0].Name.startswith(gname)]
    for idx in range(0, min(10, len(gFeatures))):
      gf = gFeatures[idx].Features[0]
      if gf.Name in gmap:
        oldEndPoints = gmap[gf.Name];
        for ep in gf.EndPoints:
          if ep[0] in oldEndPoints:
            oldEndPoints[ep[0]] = oldEndPoints[ep[0]] + ep[1]
          else:
            oldEndPoints[ep[0]] = ep[1]
      else:
        gmap[gf.Name] = {ep[0]:ep[1] for ep in gf.EndPoints}

with open(outputFile, "w") as sw:
  sw.write("File\tCategory\tFeature\tSampleRank\tOverallRank\tTotalCount\tEndposition\tPositionCount\tRelativeEndpoint\tPercentage\n")
  for groupName in groupNames:
    gmap = groupFeatureMap[groupName]
    gCountMap = {k: sum(v.values()) for k,v in gmap.iteritems()}
    gMaxCountIndexMap = {k: max(v.iteritems(), key=operator.itemgetter(1))[0] for k,v in gmap.iteritems()}
    featureRankMap = {}
    overallrank = 0
    for fname, fcount in sorted(gCountMap.iteritems(), key=lambda (k, v): (v, k), reverse=True):
      overallrank = overallrank + 1
      featureRankMap[fname] = overallrank
    
    for features in fileFeatures:
      sampleName = features[0]
      mappedFeatures = features[1]
      
      logger.info("output %s in %s ..." % (groupName, sampleName))
      gFeatures = [fg for fg in mappedFeatures if fg.Features[0].Name.startswith(groupName)]
      for idx, gfeature in enumerate(gFeatures):
        gf = gfeature.Features[0]
        featureName = gf.Name
        if featureName not in featureRankMap:
          break
        groupRank = featureRankMap[featureName]
        
        endpoints = gf.EndPoints
        positions = sorted(set(ep[0] for ep in endpoints))
        totalCount = sum(ep[1] for ep in endpoints)
        maxPosition = gMaxCountIndexMap[featureName]
        for position in positions:
          positionCount = sum(ep[1] for ep in endpoints if ep[0] == position)
          sw.write("%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.2f\n" % (sampleName, groupName, featureName, (idx + 1), groupRank, totalCount, position, positionCount, position - maxPosition, (positionCount * 1.0) / totalCount))  
logger.info("Result has been saved to %s" % outputFile)