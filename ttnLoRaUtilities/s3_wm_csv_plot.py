
# ============================================================================
# Name        : s3_wm_csv_plot.pl
# Author      : Andy Maginnis
# Version     : 1.0.0
# Copyright   : MIT (See below)
# Description : TTN data store fetch and unpack script
#
# Python plot example:
#                     CSV file read into Pandas datatable
#                     Pandas date time conversion of ASCII string
#                     Plot using the dateTime objects on the Y axis
#
# ============================================================================
# 
# MIT License
# 
# Copyright (c) 2017 Andy Maginnis
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ============================================================================

import matplotlib.pyplot as plt
import pandas as pd
from   datetime import datetime
import numpy as np
import sys, getopt
import dateutil.parser

def main(argv):

   ##--------------------------------------------------------------------------
   ## Variables
   ##--------------------------------------------------------------------------
   csvFile   = ''
   series    = 1 
   plotTitle = "LoRa WM data feed"

   ##--------------------------------------------------------------------------
   ## Commandline
   ##--------------------------------------------------------------------------
   try:
      opts, args = getopt.getopt(argv,"hc:s:",["csvFile=","series"])
   except getopt.GetoptError:
      print ('s3_wm_csv_plot.py -c <csvfile>')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
         print ('s3_wm_csv_plot.py -c <csvfile>')
         sys.exit()
      elif opt in ("-c", "--csvFile"):
         csvFile = arg
      elif opt in ("-s", "--series"):
         series = int(arg)
   print ('Input file is ' +  csvFile + ' Series is ' + str(series))
   
   ##--------------------------------------------------------------------------
   ## Plot
   ##--------------------------------------------------------------------------

   # Pandas load of data to a data array
   df=pd.read_csv(csvFile, sep=',',header=None)
      
   # Keep a record of the initial column keys
   colKeys = df.values[0,:]
   dfEndpoint = df.shape[0] - 1
   
   # replace the time key with a time string so the to_dateTime call works
   # We dont need it.
   df.loc[0,0] = df.values[1,0]

   ## Adjust time column to be time objects.
   try:
      df[0] = pd.to_datetime(df[0], format="%Y%m%d%H%M%S")
   except ValueError:
      print ('Time Column is not of format %Y%m%d%H%M%S, Trying ISO time format')
      try :
         df[0] = pd.to_datetime(df[0], format="%Y-%m-%dT%H:%M:%S.%fZ")
      except ValueError:
         print ("Time Column is not ISO time format %Y-%m-%dT%H:%M:%S.%fZ")
      
   ## Plot the average wind speed with the time as the Y axis
   print ("Data loaded, plotting Column " + str(series) + ":" + colKeys[series] + " against time.")
   plt.plot(df.values[1:dfEndpoint,0], df.values[1:dfEndpoint, series].astype(np.float))

   plt.gcf().autofmt_xdate()
   
   ## Create the title and display total data points
   plt.ylabel('WindSpeed(mph)')
   perlRocks = "%s (%d datapoints)" % (plotTitle, dfEndpoint)
   plt.title(perlRocks)

   plt.show()

if __name__ == "__main__":
   main(sys.argv[1:])

   