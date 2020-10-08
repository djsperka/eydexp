function [s] = eydexp(filename)

% eydexp - export data from asl *.eyd file. 
% S = eydexp(filename)
%

fid = fopen(filename);

s.filename = filename;

% methods below will add to s.
s = getHeader(fid, s);

% data stream is divided into segments - I guess because one can turn
% recording on and off repeatedly, recording data to the same file all the
% while. Each of those "on" periods is a segment (I completely guessed
% that, for our data we only have a single recording period for the entire
% file.

s = readSegmentDirectory(fid, s);

% we don't really need to read the overtime directory. The info we need is
% in the data records themselves, supposedly. The records here don't
% provide more info - no recovery of data, just accounting info that seems
% redundant. 
%s = readOvertimeDirectory(fid, s);

% Now start fetching records
% Note I am seeing files with only one segment, and without a segment
% directory.
s = readSegmentData(fid, s, 1);

fclose(fid);

printSummary(s);

end

% read a value off the end of a line in an eyd file. 
% many lines look like this:
%
% Update_Rate(Hz): 120
%
% The names have no spaces, and there is no space between
% the name and the colon:, so read using '%s %f', ignore the string, 
% return the number. ON ERROR JUST SET TO NEGINF. 

function [i] = readNumberFromEydLine(s)
    i = NaN;
    C=textscan(s, '%s %f');
    if ~isempty(C{2})
        i = C{2};
    end
end

% read string from end of line in an eyd file.
% For creation_Date&Time field - everything after first ':', trimmed.

function [s] = readStringFromEydLine(line)
    s = '';
    k = findstr(line, ':');
    if ~isempty(k)
        s = strtrim(line(k(1)+1:end));
    end
end

function [s] = readSegmentDirectory(fid, s)
   if isfield(s, 'nsegments') && isfield(s, 'segdiraddr')
       %fprintf(1, 'there are %d segments\n', s.nsegments);
       fseek(fid, s.segdiraddr, -1);
       s.segments = zeros(7, s.nsegments);
       % read segment records
       for i=1:s.nsegments
           b = fread(fid, 1, '*uint8');
           if b ~= hex2dec('FB')
               error('ERROR - start of segment record not found.');
           end

           seg = fread(fid, [7 1], '*uint32');
           %fprintf(1, 'seg %u %u %u %u %u %u %u\n', seg);
           s.segments(:, i) = seg;
       end
   else
       fprintf(1, 'No segment directory in this file!\n');
   end
end     


% this should be called immediately after readSegmentDirectory
% assuming that file pointer has not changed since reading segment dir.
% I think the segment directory is padded to the next 4-byte boundary.
function [s] = readOvertimeDirectory(fid, s)
    if ~feof(fid)
        fpos = ftell(fid);
        if mod(fpos, 4) 
            fseek(fid, 4-mod(fpos, 4), 0);
        end
        fprintf(1, 'reading overtime dir at filepos %u (%u)\n', ftell(fid), fpos);
        b = fread(fid, 1, '*uint8');
        if b ~= hex2dec('FC')
           fprintf(1, 'got b=%x\n', b);
           bb = fread(fid, 30, '*uint8');
           fprintf(1, '%x ', bb);

           error('ERROR - start of overtime directory not found.');
        else
           n = fread(fid, 1, '*uint32');
           fprintf(1, 'File has %d overtime records.\n', n);
           % wtf to do with these? the overtime field in each data record
           % is sufficient, nothing useful in these records.
        end

    else
        fprintf(1, 'No overtime records\n');
    end        
end

% assume that the data items ini line was read, then called here.
% should get the column headers line, then items (one per line), followed by
% an empty line (which signifies the end of the items)

function [s] = readDataItems(fid, s)
    i = 0;
    tline = fgetl(fid);
    while ischar(tline) && strip(tline)~=""
        if ~contains(tline, "Data_Item")
            C=textscan(tline, "%s %d %s %d %f");
            dtype="";
            if strcmp(C{3}, 'Byte')
                dtype='uint8';
            elseif strcmp(C{3}, 'UInt16')
                dtype = 'uint16';
            elseif strcmp(C{3}, 'Int16')
                dtype = 'int16';
            else
                error('Unknown data type');
            end
            item = struct('name', C{1}, 'position', C{2}, 'type', dtype, 'bytes', C{4}, 'scale', C{5});
            if length(item.scale) == 0
                item.scale = 1;
            end
            % now create struct if needed, else just append
            if isfield(s, 'items')
                s.items = [s.items; item];
            else
                s.items = item;
            end 
        end
        tline = fgetl(fid);
    end
end

function [s] = getHeader(fid, s)
    tline = fgetl(fid);
    while ischar(tline)
        %disp(tline)

        if contains(tline, 'Update_Rate(Hz)')
            s.rate = readNumberFromEydLine(tline);
        elseif contains(tline, 'Creation_Date')
            s.date = readStringFromEydLine(tline);
        elseif contains(tline, 'User_Recorded_Segments')
            s.nsegments = readNumberFromEydLine(tline);
        elseif  contains(tline, 'Segment_Directory_Start_Address')
            s.segdiraddr = readNumberFromEydLine(tline);
        elseif contains(tline, '[System_Data_Items]')
            s = readDataItems(fid, s);
        elseif contains(tline, '[Data_Items_Selected_by_User]')
            s = readDataItems(fid, s);
        elseif contains(tline, 'Total_Bytes_Per_Record')
            s.bpr = readNumberFromEydLine(tline);
        elseif contains(tline, '[Segment_Data]')
            s.segdata = ftell(fid);     % filepos of segment data
            break;
        end
        tline = fgetl(fid);
    end
end

function [s] = readSegmentData(fid, s, n)

    fprintf(1, 'readSegmentData: Expecting %u records in segment %u\n', s.segments(7, n), n);
    
    data = struct(  'status', zeros(s.segments(7, n), 1, 'uint8'), ...
                    'overtime', zeros(s.segments(7, n), 1, 'uint16'), ...
                    'xdat', zeros(s.segments(7, n), 1, 'uint8'), ...
                    'pupil', zeros(s.segments(7, n), 1, 'uint16'), ...
                    'x', zeros(s.segments(7, n), 1, 'double'), ...
                    'y', zeros(s.segments(7, n), 1, 'double'), ...
                    'videofield', zeros(s.segments(7, n), 1, 'uint16'));
                
    fseek(fid, s.segments(2, n), -1);
    for i = 1:s.segments(7, n)
        startrecord = fread(fid, 1, '*uint8');
        if startrecord ~= 250    % 0xFA
            bb = fread(fid, 30, '*uint8');
            fprintf(1, '%x ', bb);
            error('Error at record %u, start of record not found\n', i);
        end
        data.status(i) = fread(fid, 1, '*uint8');
        data.overtime(i) = fread(fid, 1, '*uint16');
        fseek(fid, 1, 0);   % marker - skip
        data.xdat(i) = fread(fid, 1, '*uint16');
        data.pupil(i) = fread(fid, 1, '*uint16');
        x = fread(fid, 1, '*int16');
        data.x(i) = x*0.1;
        y = fread(fid, 1, '*int16');
        data.y(i) = x*0.1;
        fseek(fid, 12, 0);
        data.videofield(i) = fread(fid, 1, '*uint16');
    end
    
    % check for end of segment?
    bb = fread(fid, 27, '*uint8');
    if feof(fid) || length(bb)~=27
        fprintf(1, 'cannot read end of segdata record?\n');
    end
    s.data = data;
end
    
function [] = printSummary(s)
    fprintf(1, '\nSummary for %s\n', s.filename);
    fprintf(1, 'created : %s\n', s.date);
    fprintf(1, 'rate(Hz): %u\n', s.rate);
    fprintf(1, '# segments: %u\n', s.nsegments);
    for i=1:s.nsegments
        fprintf(1, 'Segment %u:\n', i);
        fprintf(1, 'Start frame: %u\n', s.segments(3, i));
        fprintf(1, 'End frame  : %u\n', s.segments(4, i));
        fprintf(1, 'num records: %u (expect %u)\n', s.segments(7, i), s.segments(4, i)-s.segments(3, i));
        fprintf(1, 'overtime (s/b=0): %u\n', sum(s.data.overtime(i)));
    end
    
end

