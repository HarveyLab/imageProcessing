function TrackSegments(fullfilename,movie_file,maxShift,nSegments)

MovFile = matfile([movie_file '.mat'],'Writable',true);
%% Load tiff File
t=Tiff(fullfilename);
N = t.getTag('ImageLength');
M = t.getTag('ImageWidth');
t.setDirectory(1);
while ~t.lastDirectory
    t.nextDirectory;
end
Z = t.currentDirectory;
mov = zeros(N,M,Z,'single');
for frame = 1:Z
    t.setDirectory(frame);
    mov(:,:,frame) = t.read;  
    if ~mod(frame, 100)
        fprintf('%1.0f frames loaded.\n', frame);
    end
end

%% Clip bad image region 
if isempty(MovFile.movie_mask)
    refWin=mean(mov,3);
    imshow(histeq(refWin/max(refWin(:)))),
    h=imrect;
    pause;
    movie_mask = round(getPosition(h));
    MovFile.movie_mask = movie_mask;
else
    movie_mask = MovFile.movie_mask;
end
mov = mov(movie_mask(2):movie_mask(2)+movie_mask(4),movie_mask(1):movie_mask(1)+movie_mask(3),:);
M=movie_mask(3)+1;
N=movie_mask(4)+1;

%% Construct Movie Segments
segPos = [];
switch nSegments
    case 9
        xind = floor(linspace(1,M/2,3));
        yind = floor(linspace(1,N/2,3));
    case 6
        xind = floor(linspace(1,M/2,2));
        yind = floor(linspace(1,N/2,3));
    case 4
        xind = floor(linspace(1,M/2,2));
        yind = floor(linspace(1,N/2,2));  
end
        
for x=1:length(xind)
    for y=1:length(yind)
        segPos(end+1,:) = [xind(x) yind(y)  floor(M/2) floor(N/2)];
    end
end
nSeg = size(segPos,1);
MovFile.segPos = segPos;

%% First order motion correction
%Break Movie into Sliced Segments and clear original
for Seg = 1:nSeg
    MovCell{Seg} = mov(segPos(Seg,2):segPos(Seg,2)+segPos(Seg,4),segPos(Seg,1):segPos(Seg,1)+segPos(Seg,3),:);
end
clear mov,

parfor Seg = 1:nSeg
    display(sprintf('Segment: %d',Seg)),
    tMov = MovCell{Seg};
    tFrame = mean(tMov,3); 
    tBase = prctile(tFrame(:),1);
    tTop = prctile(tFrame(:),95);
    tMov = (tMov - tBase) / (tTop-tBase);
    tMov(tMov<0) = 0; tMov(tMov>1) = 1;
[xshifts(Seg,:),yshifts(Seg,:)]=track_subpixel_wholeframe_motion_varythresh(...
    tMov,median(tMov,3),maxShift,0.9,100);
end

%rebuild movie from segments and clear segs
switch nSegments
    case 9
        UpLeft = 1; DownLeft = 3; UpRight = 7; DownRight = 9;
    case 6
        UpLeft = 1; DownLeft = 3; UpRight = 4; DownRight = 6;
    case 4
        UpLeft = 1; DownLeft = 2; UpRight = 3; DownRight = 4; 
end

mov = cat(2,cat(1,MovCell{UpLeft}(1:end-2,1:end-2,:),MovCell{DownLeft}(1:end,1:end-2,:)),cat(1,MovCell{UpRight}(1:end-2,:,:),MovCell{DownRight}));
clear MovCell

%Calculate correction for reference image and crop
refFrame = median(AcquisitionCorrect(mov,mean(xshifts),mean(yshifts)),3);
refFrame = refFrame(1+maxShift:end-maxShift,1+maxShift:end-maxShift,:);

%Save results to disk
acqFrames = MovFile.acqFrames;
startFrame = sum(acqFrames)+1;
endFrame = startFrame+Z-1;
MovFile.acqFrames = cat(1,acqFrames,Z);
MovFile.cated_xShift(1:nSeg,startFrame:endFrame) = xshifts;
MovFile.cated_yShift(1:nSeg,startFrame:endFrame) = yshifts;
MovFile.acqRef(1:size(refFrame,1),1:size(refFrame,2),length(MovFile.acqFrames)+1) = refFrame;