# eydexp
Matlab script for exporting ASL eyd file data. 

```shell
s=eydexp('2020-09-25-13.59.48.eyd');
readSegmentData: Expecting 62662 records in segment 1

Summary for 2020-09-25-13.59.48.eyd
created : 9/25/2020 1:59:48 PM
rate(Hz): 240
# segments: 1
Segment 1:
Start frame: 12093457
End frame  : 12219147
num records: 62662 (expect 125690)
overtime (s/b=0): 0
```

The struct 's.data' has the actual data records. 
* records are one-per-camera image. Camera rate is 's.rate' (Hz). 
* s.data.status - check bits for data quality 
* s.data.xdat - check bits for sync markers
* s.data.pupil - pupil diameter (check status bits first)
