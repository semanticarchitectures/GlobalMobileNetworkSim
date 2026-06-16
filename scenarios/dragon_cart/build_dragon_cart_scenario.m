function scenario = build_dragon_cart_scenario()
% Dragon Cart UAS Swarm — C-130 from Cape Cod Air Station
scenario.scenarioName = 'DragonCartSwarm';
scenario.simulationDurationSec = 7200;

bg_low = struct('distribution','uniform','min',0.0,'max',0.1);
bg_med = struct('distribution','uniform','min',0.1,'max',0.3);
od_exp = struct('distribution','exponential','mean',30);
od_fix = struct('distribution','fixed','value',10);

% C-130
c130.id='C130'; c130.type='Mobile';
c130.lat=41.66; c130.lon=-70.52; c130.altM=0;
c130.keplerElements=[];
c130.trajectory.type='waypoints';
c130.trajectory.waypoints=struct('timeSec',{0,300,1800,2700,3600,5400,6000,7200},'lat',{41.66,41.70,41.80,41.90,41.80,41.70,41.66,41.66},'lon',{-70.52,-70.00,-66.00,-62.00,-66.00,-70.00,-70.52,-70.52},'altM',{0,7500,7500,6000,7500,3000,0,0});

% GCC
gcc.id='GCC'; gcc.type='Stationary';
gcc.lat=41.66; gcc.lon=-70.52; gcc.altM=10;
gcc.trajectory=[]; gcc.keplerElements=[];

% LEO satellites
leo1.id='LEO_SAT_1'; leo1.type='Mobile'; leo1.lat=0; leo1.lon=0; leo1.altM=550000; leo1.trajectory=[];
leo1.keplerElements=struct('semiMajorAxisM',6928000,'eccentricity',0.0001,'inclinationDeg',53,'raanDeg',30,'argPeriapsisDeg',0,'trueAnomalyDeg',60,'epochSec',0);
leo2.id='LEO_SAT_2'; leo2.type='Mobile'; leo2.lat=0; leo2.lon=0; leo2.altM=550000; leo2.trajectory=[];
leo2.keplerElements=struct('semiMajorAxisM',6928000,'eccentricity',0.0001,'inclinationDeg',53,'raanDeg',120,'argPeriapsisDeg',0,'trueAnomalyDeg',240,'epochSec',0);

% ISR drones
isr_lats=[42.50,41.30,42.70,41.10]; isr_lons=[-61.00,-61.00,-63.00,-63.00];
isr_nodes=cell(4,1);
for k=1:4
  nd.id=sprintf('ISR_%d',k); nd.type='Mobile'; nd.lat=41.90; nd.lon=-62.00; nd.altM=3000; nd.keplerElements=[];
  nd.trajectory.type='waypoints';
  nd.trajectory.waypoints=struct('timeSec',{2700,3000,4200,7200},'lat',{41.90,(41.90+isr_lats(k))/2,isr_lats(k),isr_lats(k)},'lon',{-62.00,(-62.00+isr_lons(k))/2,isr_lons(k),isr_lons(k)},'altM',{6000,3000,3000,3000});
  isr_nodes{k}=nd;
end

% Relay drones
rel_lats=[42.00,41.80,42.00,41.80]; rel_lons=[-62.00,-62.00,-61.00,-61.00];
rel_nodes=cell(4,1);
for k=1:4
  nd.id=sprintf('RELAY_%d',k); nd.type='Mobile'; nd.lat=41.90; nd.lon=-62.00; nd.altM=5000; nd.keplerElements=[];
  nd.trajectory.type='waypoints';
  nd.trajectory.waypoints=struct('timeSec',{2760,3060,7200},'lat',{41.90,rel_lats(k),rel_lats(k)},'lon',{-62.00,rel_lons(k),rel_lons(k)},'altM',{6000,5000,5000});
  rel_nodes{k}=nd;
end

% Strike drones
str_lats=[42.10,41.60,42.40,41.40]; str_lons=[-59.50,-59.50,-59.00,-59.00];
str_nodes=cell(4,1);
for k=1:4
  nd.id=sprintf('STRIKE_%d',k); nd.type='Mobile'; nd.lat=41.90; nd.lon=-62.00; nd.altM=500; nd.keplerElements=[];
  nd.trajectory.type='waypoints';
  nd.trajectory.waypoints=struct('timeSec',{2820,3120,3600,7200},'lat',{41.90,(41.90+str_lats(k))/2,str_lats(k),str_lats(k)},'lon',{-62.00,(-62.00+str_lons(k))/2,str_lons(k),str_lons(k)},'altM',{6000,500,300,300});
  str_nodes{k}=nd;
end

% Recovery drones
rec_offsets=[0.0,0.05,-0.05,0.10];
rec_nodes=cell(4,1);
for k=1:4
  nd.id=sprintf('RECOV_%d',k); nd.type='Mobile'; nd.lat=41.90; nd.lon=-62.00; nd.altM=3000; nd.keplerElements=[];
  nd.trajectory.type='waypoints';
  nd.trajectory.waypoints=struct('timeSec',{2880,3180,4500,5400,6000,7200},'lat',{41.90,41.85+rec_offsets(k),41.80+rec_offsets(k),41.75+rec_offsets(k),41.70+rec_offsets(k),41.66},'lon',{-62.00,-63.00,-65.00,-67.00,-69.50,-70.52},'altM',{6000,3000,3000,3000,1000,0});
  rec_nodes{k}=nd;
end

all_nodes=[c130,gcc,leo1,leo2];
for k=1:4; all_nodes(end+1)=isr_nodes{k}; end
for k=1:4; all_nodes(end+1)=rel_nodes{k}; end
for k=1:4; all_nodes(end+1)=str_nodes{k}; end
for k=1:4; all_nodes(end+1)=rec_nodes{k}; end
scenario.nodes=all_nodes;

% Links
links=struct('id',{},'type',{},'srcNodeId',{},'dstNodeId',{},'nominalLatencyMs',{},'bandwidthBps',{},'outageRate',{},'outageDuration',{},'backgroundTraffic',{},'coverageRadiusM',{},'congestionPenaltyMs',{});
links(end+1)=mklink('C130_GCC','Line_Of_Sight','C130','GCC',2,500000,0,od_fix,bg_low,500000,0);
links(end+1)=mklink('GCC_C130','Line_Of_Sight','GCC','C130',2,500000,0,od_fix,bg_low,500000,0);
links(end+1)=mklink('C130_LEO1','LEO_Satellite','C130','LEO_SAT_1',30,2e6,0.003,od_exp,bg_low,NaN,50);
links(end+1)=mklink('LEO1_C130','LEO_Satellite','LEO_SAT_1','C130',30,2e6,0.003,od_exp,bg_low,NaN,50);
links(end+1)=mklink('C130_LEO2','LEO_Satellite','C130','LEO_SAT_2',35,2e6,0.003,od_exp,bg_low,NaN,50);
links(end+1)=mklink('LEO2_C130','LEO_Satellite','LEO_SAT_2','C130',35,2e6,0.003,od_exp,bg_low,NaN,50);
links(end+1)=mklink('GCC_LEO1','LEO_Satellite','GCC','LEO_SAT_1',28,50e6,0.002,od_exp,bg_med,NaN,30);
links(end+1)=mklink('LEO1_GCC','LEO_Satellite','LEO_SAT_1','GCC',28,50e6,0.002,od_exp,bg_med,NaN,30);
links(end+1)=mklink('GCC_LEO2','LEO_Satellite','GCC','LEO_SAT_2',32,50e6,0.002,od_exp,bg_med,NaN,30);
links(end+1)=mklink('LEO2_GCC','LEO_Satellite','LEO_SAT_2','GCC',32,50e6,0.002,od_exp,bg_med,NaN,30);
for r=1:4
  rid=sprintf('RELAY_%d',r);
  links(end+1)=mklink(sprintf('%s_LEO1',rid),'LEO_Satellite',rid,'LEO_SAT_1',35,1e6,0.005,od_exp,bg_low,NaN,80);
  links(end+1)=mklink(sprintf('LEO1_%s',rid),'LEO_Satellite','LEO_SAT_1',rid,35,1e6,0.005,od_exp,bg_low,NaN,80);
  links(end+1)=mklink(sprintf('C130_%s',rid),'Line_Of_Sight','C130',rid,2,1e6,0,od_fix,bg_low,300000,0);
  links(end+1)=mklink(sprintf('%s_C130',rid),'Line_Of_Sight',rid,'C130',2,1e6,0,od_fix,bg_low,300000,0);
end
for i=1:4; for r=1:4
  isrId=sprintf('ISR_%d',i); relId=sprintf('RELAY_%d',r);
  links(end+1)=mklink(sprintf('%s_%s',isrId,relId),'Line_Of_Sight',isrId,relId,2,500000,0,od_fix,bg_low,200000,0);
  links(end+1)=mklink(sprintf('%s_%s',relId,isrId),'Line_Of_Sight',relId,isrId,2,500000,0,od_fix,bg_low,200000,0);
end; end
for s=1:4; for r=1:4
  strId=sprintf('STRIKE_%d',s); relId=sprintf('RELAY_%d',r);
  links(end+1)=mklink(sprintf('%s_%s',strId,relId),'Line_Of_Sight',strId,relId,2,200000,0,od_fix,bg_low,200000,0);
  links(end+1)=mklink(sprintf('%s_%s',relId,strId),'Line_Of_Sight',relId,strId,2,200000,0,od_fix,bg_low,200000,0);
end; end
for v=1:4; for r=1:4
  recId=sprintf('RECOV_%d',v); relId=sprintf('RELAY_%d',r);
  links(end+1)=mklink(sprintf('%s_%s',recId,relId),'Line_Of_Sight',recId,relId,2,500000,0,od_fix,bg_low,200000,0);
  links(end+1)=mklink(sprintf('%s_%s',relId,recId),'Line_Of_Sight',relId,recId,2,500000,0,od_fix,bg_low,200000,0);
end; end
for v=1:4
  recId=sprintf('RECOV_%d',v);
  links(end+1)=mklink(sprintf('%s_GCC',recId),'Line_Of_Sight',recId,'GCC',2,500000,0,od_fix,bg_low,400000,0);
  links(end+1)=mklink(sprintf('GCC_%s',recId),'Line_Of_Sight','GCC',recId,2,500000,0,od_fix,bg_low,400000,0);
end
scenario.links=links;

% C2 Messages
msgs=struct('id',{},'srcNodeId',{},'dstNodeId',{},'sizeBytes',{},'scheduledTimeSec',{});
msgs(end+1)=mkmsg('m01','GCC','C130',2048,600);
msgs(end+1)=mkmsg('m02','GCC','C130',4096,1800);
msgs(end+1)=mkmsg('m03','C130','GCC',256,2700);
msgs(end+1)=mkmsg('m04','C130','GCC',256,2760);
msgs(end+1)=mkmsg('m05','C130','GCC',256,2820);
msgs(end+1)=mkmsg('m06','C130','GCC',256,2880);
for k=1:4; msgs(end+1)=mkmsg(sprintf('m%02d',6+k),sprintf('ISR_%d',k),'GCC',512,3600); end
for k=1:4; msgs(end+1)=mkmsg(sprintf('m%02d',10+k),'GCC',sprintf('STRIKE_%d',k),256,3000); end
for k=1:4; msgs(end+1)=mkmsg(sprintf('m%02d',14+k),sprintf('STRIKE_%d',k),'GCC',1024,3700); end
for k=1:4; msgs(end+1)=mkmsg(sprintf('m%02d',18+k),sprintf('RECOV_%d',k),'GCC',8192,5400); end
msgs(end+1)=mkmsg('m23','C130','GCC',256,4500);
msgs(end+1)=mkmsg('m24','C130','GCC',256,5800);
scenario.c2Messages=msgs;
end

function lk=mklink(id,tp,src,dst,lat,bw,or_,od,bg,cov,cong)
lk.id=id; lk.type=tp; lk.srcNodeId=src; lk.dstNodeId=dst;
lk.nominalLatencyMs=lat; lk.bandwidthBps=bw; lk.outageRate=or_;
lk.outageDuration=od; lk.backgroundTraffic=bg;
lk.coverageRadiusM=cov; lk.congestionPenaltyMs=cong;
end

function m=mkmsg(id,src,dst,sz,t)
m.id=id; m.srcNodeId=src; m.dstNodeId=dst; m.sizeBytes=sz; m.scheduledTimeSec=t;
end
