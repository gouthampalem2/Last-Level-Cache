import my_pkg::*;
module LLC_13;//(input logic [31:0]addr);

  real hit_count;
  real miss_count;
  int way_evict;
  int cache_reads;
  int cache_writes;
  real hit_ratio;
  //status hit_miss;
  mesi_bits mesiBits,temp_mb;
  string LineStatus;
  //array of cache sets
  set cache[32767:0];
  //array of cache copies
  set_copy cache_copy[32767:0];

  int fd,status,command,dm; 
  string mode, debug_mode,file_name;
  logic [31:0]addr;


   initial begin
	if($value$plusargs("MODE=%s",mode)) begin
		if(mode == "N") 		
			$display("Normal Running Mode");
		else if(mode == "S")
			$display("Silent Running Mode");
		else 
			$display("NO RUNNING MODE PROVIDED");
	end

	dm = $value$plusargs("DEBUG_MODE=%s",debug_mode);
	if($value$plusargs("FILE_NAME=%s",file_name)) begin
		fd = $fopen (file_name, "r");
		while(!$feof(fd)) begin // fscanf returns the number of matches
			status=$fscanf (fd, "%d %h", command, addr); 
			$display ("Sending command = %0d address = %0h", command, addr);
			AddressDivision(addr,command);
			$display("===========================================================");
		end
		$fclose(fd); // Close this file handle
		hit_ratio = (hit_count)/(hit_count+miss_count);
		$display("Hit ratio for trace file: %s with hit count=%0f miss count=%0f is = %4.2f",file_name,hit_count,miss_count,hit_ratio);
		
	end   
    end


/* AddressDivision function partitions the address into ByteSelect, Index, Tag */

 function void AddressDivision(input logic [31:0]addr, input int command);
	logic [14:0]Index;
    	logic [10:0]Tag;
	logic [5:0]ByteSelect;


	parameter BITS_FOR_BYTE_OFFSET = $clog2(SIZE_OF_EACH_CACHE_LINE);
	parameter BITS_FOR_INDEX       = $clog2(CAPACITY/(SIZE_OF_EACH_CACHE_LINE*NUMBER_OF_WAYS));
	parameter BITS_FOR_TAG         = SIZE_OF_ADDRESS - (BITS_FOR_BYTE_OFFSET+BITS_FOR_INDEX);
	
	Tag                  = addr[SIZE_OF_ADDRESS-1:(BITS_FOR_BYTE_OFFSET+BITS_FOR_INDEX)];
	Index                = addr[(BITS_FOR_BYTE_OFFSET+BITS_FOR_INDEX-1):BITS_FOR_BYTE_OFFSET];
    	ByteSelect           = addr[(BITS_FOR_BYTE_OFFSET-1):0];	

	$display("ADDR %0h is patitioned as Tag %0h Indx %0h ByteSelect %0h",addr,Tag,Index,ByteSelect);
	CacheOperations(addr,Tag,Index,ByteSelect,command);

 endfunction

/*function to update PLRU bits*/
function void UpdateLRU(input int set, way);
	if(way>=4) begin
	  cache[set].PLRU[0]=1;
	    if(way>=6) begin
      		cache[set].PLRU[2]=1;
      	 	if(way==6) cache[set].PLRU[6]=0;
      		else cache[set].PLRU[6]=1;
   	    end else begin
      		cache[set].PLRU[2]=0;
      		if(way==4) cache[set].PLRU[5]=0;
      		else cache[set].PLRU[5]=1;
    	    end
 	end else begin
  	   cache[set].PLRU[0]=0;
  	   if(way>=2) begin
    		cache[set].PLRU[1]=1;
    		if(way==2) cache[set].PLRU[4]=0;
    		else cache[set].PLRU[4]=1;
  	   end else begin
    		cache[set].PLRU[1]=0;
    		if(way==1) cache[set].PLRU[3]=1;
    		else cache[set].PLRU[3]=0;
  	   end
	end

	//DEBUG_MODE PRINT
	if(debug_mode == "GET_DISPLAYS")
		$display("PLRU bits are %0b",cache[set].PLRU);

endfunction

/* WhichWay function will be called when all the ways are filled, and will give the way which we need to evict*/
function int WhichWay(input int set);
    	int way;
    	if(cache[set].PLRU[0]==0) begin
      		if(cache[set].PLRU[2]==0) begin
        		if(cache[set].PLRU[6]==0) 
          			way = 7;
        		else
          			way = 6;	
      		end else begin
        		if(cache[set].PLRU[5]==0)
          			way = 5;
        		else
          			way = 4;
      		end
    	end else begin
      		if(cache[set].PLRU[1]==0) begin
        		if(cache[set].PLRU[4]==0) 
          			way = 3;
        		else
          			way=2;
      		end else begin
        		if(cache[set].PLRU[3]==0)
          			way = 1;
        		else
          			way = 0;
      		end
    	end
    return way;

endfunction


function void CacheOperations(input logic[31:0]Addr, input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input int command);
	
	string snoopResult;

	  if(command ==8 || command==9) begin 
 		temp_mb = MESIProtocol( 0,0,0,0,command,0,"");
	  end else begin
		for(int j=0;j<8;j++) begin	
		    if(cache[Index].Way[j].state == I) begin 
			  miss_count=miss_count+1;
			  if(miss_count==1) $display("This addr %0h is a compulsory miss ",Addr);
			  else $display("Ohh!!! :( It's a Miss!!");
			  LineStatus = "MISS";
			  cache[Index].Way[j].tag_bits = Tag;
			  cache[Index].Way[j].state = MESIProtocol(cache[Index].Way[j].tag_bits,Index,ByteSelect,addr,command,j,LineStatus);
			  UpdateLRU(Index,j);
			  if(mode=="N") begin
				if(command == 0)
					BusOperation("BUSRD",Addr,snoopResult);
				else if(command == 1) 
					BusOperation("RDWIM",Addr,snoopResult);
				/*if(command == 0) begin
					if(snoopResult == "HIT" || snoopResult == "HITM")
						MessageToCache(" is a MISS :( So get line from other Cache and update in our LLC so send line to Lower level cache also",addr);
					else 
						MessageToCache(" is a MISS :( So get line from DRAM and update in our LLC so send line to Lower level cache also",addr);
				end else if(command == 1) begin
					MessageToCache("is MISS so got line from DRAM to Last Level Cache update required bytes and  send line to Low level cache also",addr);
				end*/
			   end
			  cache_copy[Index].Way[j].addr = Addr;
			  cache_copy[Index].PLRU = cache[Index].PLRU;
			  cache_copy[Index].Way[j].tag_bits = cache[Index].Way[j].tag_bits;
			  cache_copy[Index].Way[j].state = cache[Index].Way[j].state;
			  break;
		     end else begin
			  if(cache[Index].Way[j].tag_bits == Tag) begin
				$display("YAY!!!! Got A HIT");
				hit_count = hit_count+1;
				LineStatus = "HIT";
				cache[Index].Way[j].state = MESIProtocol(cache[Index].Way[j].tag_bits,Index,ByteSelect,addr,command,j,LineStatus);
				UpdateLRU(Index,j); 
				/*if(mode=="N") begin
				   if(command == 0)
					MessageToCache("It is hit in Last Level Cache so send line to Low level cache also",addr);
					   //else if(command == 1)
				end*/
				cache_copy[Index].Way[j].addr = Addr;
				cache_copy[Index].PLRU = cache[Index].PLRU;
				cache_copy[Index].Way[j].tag_bits =cache[Index].Way[j].tag_bits ;
				cache_copy[Index].Way[j].state = cache[Index].Way[j].state;
				break;
			  end else begin
				if(j==7) begin
					$display("It's a conflict Miss!! find a way to EVICT");
					miss_count = miss_count+1;
					LineStatus = "MISS";
					way_evict = WhichWay(Index);
					UpdateLRU(Index,way_evict); 
					$display("way %0d will be evicted!!",way_evict);
					MessageToCache("Evicting Line in LLC, invalidate L1 copy if present",Addr);
					BusOperation("BUSWR",Addr,snoopResult);
					if(command == 0 || command == 2)
						BusOperation("BUSRD",Addr,snoopResult);
					else if(command == 1)
						BusOperation("RWIM",Addr,snoopResult);
					cache[Index].Way[way_evict].state = I;
					cache[Index].Way[way_evict].tag_bits = Tag;
					cache[Index].Way[way_evict].state = MESIProtocol(cache[Index].Way[way_evict].tag_bits,Index,ByteSelect,addr,command,way_evict,LineStatus);
					if(debug_mode == "GET_DISPLAYS") begin
						$display("AFTER CACHEING tag is %0h",cache[Index].Way[way_evict].tag_bits);
						$display("AFTER:: at set %0h -> %0p",Index,cache[Index]);
					end
					cache_copy[Index].Way[way_evict].addr = Addr;
					cache_copy[Index].PLRU = cache[Index].PLRU;
					cache_copy[Index].Way[way_evict].tag_bits = cache[Index].Way[j].tag_bits;
					cache_copy[Index].Way[way_evict].state = cache[Index].Way[way_evict].state;
					break;
				end else
					continue;
			end
		 end
	    end
	$display("AFTER:: at set %0h -> %0p",Index,cache[Index]);
	$display("After End of CacheOperations for addr %0h, hit count = %0f miss count = %0f cache_reads = %0d cache_writes=%0d",Addr,hit_count,miss_count,cache_reads,cache_writes);
        end

endfunction

/*This function implements MESI protocol for each cache line*/
function mesi_bits MESIProtocol(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [31:0]addr,input int command,input logic [3:0]way_number,input string lineStatus);

	mesi_bits LineState;
	if(debug_mode == "GET_DISPLAYS")
		$display("CALLED MESIProtocol func for Index %0h addr %0h command %0d",Index,addr,command);
	case(command)
		0: LineState = L1DCRdReq(Tag,Index,ByteSelect,way_number,lineStatus);
		1: LineState = L1WrReq(Tag,Index,ByteSelect,way_number,lineStatus);
		2: LineState = L1ICRdReq(Tag,Index,ByteSelect,way_number,lineStatus); 
		3: LineState = SnoopedInvalidate(Tag,Index,ByteSelect,addr,way_number,lineStatus);
		4: LineState = SnoopedRdReq(Tag,Index,ByteSelect,addr,way_number,lineStatus);
		5: LineState = SnoopedWrReq(Tag,Index,ByteSelect,way_number,lineStatus);
		6: LineState = SnoopedRdWithIntendToModify(Tag,Index,ByteSelect,way_number,lineStatus);
		8: ClearNReset();
		9: PrintContentNStateV();
	endcase
    return LineState;

endfunction

/*In this function we are considering last two bits of ByteSelect to get the snoop result of other Pr*/
function string GetSnoopResult(input logic [5:0]ByteSelect);

	if(ByteSelect[1:0] == 2'b00) 
		return "HIT";
	else if(ByteSelect[1:0] == 2'b01)
		return "HITM";
	else 
		return "NOHIT";

endfunction

/*In this function our cache is giving output of the snoop*/
function void PutSnoopResult(input logic [31:0]addr,input string SnoopResult);
	
	if(mode == "N") 
	  $display("SnoopResult for Address %0h is %0h",addr,SnoopResult);
endfunction

/*To maintain inclusivity we are using this function to inform L1*/
function void MessageToCache(input string Message, input logic [31:0]addr);

	if(mode == "N") 
	  $display("Address %0h, %s",addr,Message);

endfunction

/*Here we are */
function void BusOperation(input string BusOp, input bit [31:0]addr, output string SnoopResult);

	SnoopResult = GetSnoopResult(addr[5:0]); 
        $display("BusOp %s Address %0h",BusOp,addr);

endfunction

function mesi_bits L1DCRdReq(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [3:0]way_number,input string LineStatus);
	string snoopResult;
	$display("Received L1 Rd from data cache for addr %0h",addr);

	if(LineStatus == "HIT") begin
		cache[Index].Way[way_number].state = cache[Index].Way[way_number].state;
	end else begin
		snoopResult = GetSnoopResult(ByteSelect);
		if(debug_mode == "GET_DISPLAYS") $display("snoopResult from GetSnoop to know %s",snoopResult);
		if(cache[Index].Way[way_number].state == I) begin
			if(snoopResult == "HIT" || snoopResult == "HITM") 
				cache[Index].Way[way_number].state = S;
			else 
				cache[Index].Way[way_number].state = E;
		end 
	end
	if(debug_mode == "GET_DISPLAYS") $display("At the end of ProcessorRd for addr %0h Print state %s SnoopResult %b",addr,cache[Index].Way[way_number].state,snoopResult);
	  cache_reads = cache_reads +1;
	 return cache[Index].Way[way_number].state;

endfunction

/* 2 or 3 NOHIT 0 HIT 1 HITM*/
function mesi_bits L1ICRdReq(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [3:0]way_number,input string LineStatus);
	string snoopResult;
	
	$display("Received L1 Rd from Instruction cache for addr %0h",addr);

	if(LineStatus == "HIT") begin
		cache[Index].Way[way_number].state = cache[Index].Way[way_number].state;
	end else begin
		snoopResult = GetSnoopResult(ByteSelect);
		if(debug_mode == "GET_DISPLAYS") $display("snoopResult from GetSnoop to know %s",snoopResult);
		if(cache[Index].Way[way_number].state == I) begin
			if(snoopResult == "HIT" || snoopResult == "HITM") 
				cache[Index].Way[way_number].state = S;
			else 
				cache[Index].Way[way_number].state = E;
		end 
	end
	if(debug_mode == "GET_DISPLAYS") $display("At the end of ProcessorRd for addr %0h Print state %s SnoopResult %b",addr,cache[Index].Way[way_number].state,snoopResult);
	  cache_reads = cache_reads +1;

	 return cache[Index].Way[way_number].state;
endfunction

/**/
function mesi_bits L1WrReq(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [3:0]way_number,input string LineStatus);
	logic [31:0]addr;

	addr = {Tag,Index,ByteSelect};
	if(cache[Index].Way[way_number].state == I) begin
		cache[Index].Way[way_number].state = M;
		$display("Addr %0h %s",addr,"RDWIM"); 
	end else if(cache[Index].Way[way_number].state == S) begin
		cache[Index].Way[way_number].state = M;
		$display("Addr %0h %s",addr,"BusUpGdr");
		//PutSnoopResult(addr, "BusUpGdr");
	end else if(cache[Index].Way[way_number].state == E) begin
		cache[Index].Way[way_number].state = M;
	end else
		cache[Index].Way[way_number].state = M;
	$display("At the end of PWR for addr %0h Print state %s",addr,cache[Index].Way[way_number].state);
	cache_writes = cache_writes+1;
	return cache[Index].Way[way_number].state;
endfunction

/**/
function mesi_bits SnoopedInvalidate(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [31:0]addr,input logic [3:0]way_number,input string LineStatus);

	cache[Index].Way[way_number].state = I;
	MessageToCache("In Bus invalidate function, we made addr %0h Invalid in L1 if present",addr);

	return cache[Index].Way[way_number].state;

endfunction

/**/
function mesi_bits SnoopedRdReq(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [31:0]addr,input logic [3:0]way_number,input string LineStatus);

	string snoopResult;

	if(cache[Index].Way[way_number].state == M) begin
		PutSnoopResult(addr,"HIT to a modified line");
		cache[Index].Way[way_number].state = S;
		snoopResult = "HITM";
		BusOperation("BusWr",addr,snoopResult);//PutSnoopResult(addr,"Bus");
	end else if(cache[Index].Way[way_number].state == E) begin
		cache[Index].Way[way_number].state = S;
		PutSnoopResult(addr,"It's a HIT in our cache");
	end else cache[Index].Way[way_number].state = cache[Index].Way[way_number].state;


	return cache[Index].Way[way_number].state;

endfunction

/**/
function mesi_bits SnoopedWrReq(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [3:0]way_number,input string LineStatus);

	 cache[Index].Way[way_number].state = cache[Index].Way[way_number].state; 
	
	 return cache[Index].Way[way_number].state;
endfunction

/**/
function mesi_bits SnoopedRdWithIntendToModify(input logic [10:0]Tag, input logic [14:0]Index,input logic [5:0]ByteSelect,input logic [3:0]way_number,input string LineStatus);

	string snoopResult;
	if(cache[Index].Way[way_number].state == E || cache[Index].Way[way_number].state == S || cache[Index].Way[way_number].state == I) begin
		cache[Index].Way[way_number].state = I;
	end else begin
		cache[Index].Way[way_number].state = I;
		snoopResult = "HITM";
		BusOperation("BusWr",addr,snoopResult);
		PutSnoopResult(addr,"Flush the copy to DRAM");
	end
	$display("At the end of BusIntend modify for Print state %s",cache[Index].Way[way_number].state);

	return cache[Index].Way[way_number].state;
endfunction


/*This function sets all the lines to Invalid*/
function void ClearNReset();

	for(int idx=0;idx<32767;idx++) begin
   		for(int j=0;j<8;j++) begin
			cache[idx].Way[j].state = I;
   		end
	end

        //return cache[Index].Way[way_number].state;

endfunction

/*This function prints contents of valid cachelines*/
function void PrintContentNStateV();

	for(int indx=0;indx<32767;indx++) begin
   	  for(int j=0;j<8;j++) begin
		if(cache[indx].Way[j].state != I) begin
		    $display("valid addr = %0h PLRU bits = %0b Set number = %0h state = %0s Tag bits = %0h ",cache_copy[indx].Way[j].addr,cache_copy[indx].PLRU,indx,cache_copy[indx].Way[j].state,cache_copy[indx].Way[j].tag_bits);
		end
	  end
	end

endfunction

endmodule
