#!/bin/bash 
#mencoder $OPTS -o jiggly-tlibig9-JackieDaniels.avi \
#jiggly-tlibig9-cd1.avi -ss 01:17:00  \
#jiggly-tlibig9-cd2.avi -endpos 00:10:30

OPTS="-include mencoder.conf -profile copy"

mencoder $OPTS -o swe6-cps17_KarinaOReilley.avi \
swe6-cps17a.avi -ss 00:10:00 -endpos 00:16:05
