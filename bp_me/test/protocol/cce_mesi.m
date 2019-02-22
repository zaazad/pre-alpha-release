-- Tavio Guarino
-- referenced from Meghan Cowan (cowanmeg)
-- four-state, MESI protocol

----------------------------------------------------------------------
-- First model assumptions
----------------------------------------------------------------------
-- 999999 for val is smaller than the state space allowing us to 
-- compare values for coherence after writes
-- NO MODEL OF CACHE TO CACHE TRANSFER
-- WHEN MODIFIED THE NEW VALUE IS DIFFERENT FROM THE CCE VALUE TILL WRITEBACK
-- To model pending and blocking states rules are defined to create 
-- blocks or pending on the lines

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
const 
  n_lce: 3;     -- number of LCE's
  lce_req: 0;
  lce_resp: 1;
  lce_data_resp: 2;
  lce_cmd: 3;
  lce_data_cmd: 4;
  num_net: 5;

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------
type

  LCErange: 0..(n_lce-1);        -- LCE's identifiers
  LCEcounterRange: 0..n_lce;     -- Used to count number of LCE sharers
  CacheLine: 0..1;                  -- valid cache line identifiers 0 or 1 (aka 2 data sets)
  StateType: enum { M, E, S, I};    -- Used to cycle through types
  LCEReqType: enum { R, W, EM, N}; -- To keep track of operation that was blocked for cacheline Read, Wrtie, Evict modified, None
  Value: 0..999999;               -- Used as an indicator of the cache lines value
  --Pending_req_Q: array []

  CCEState:
    Record
      state: StateType;           
      owner: array [LCErange] of boolean;   -- Is it an owner of the cacheline or not  
      val: Value;                         -- need this here in case all lines invalid reassign value after read/write req     
      pending: boolean;                     -- whether or not the cache line is pending response from mem           
    End;

  LCEState:
    Record
      state: StateType;     
      owner: boolean;                       -- Is it an owner of the cacheline or not 
      val: Value;                         -- assuming less state space than this if not increase number
      blocking: boolean;                    -- whether or not LCE is waiting for operation to complete
      blockd_req: LCEReqType;               -- Used to hold what kind of op was blocked for cacheline
    End;


----------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------
var
  --all the lce's with array of cachelines
  LCEs: array [LCErange] of array[CacheLine] of LCEState; 
  CCEdir: array [CacheLine] of CCEState;


----------------------------------------------------------------------
-- procedures
----------------------------------------------------------------------
procedure ReadReq(lce: LCErange; cl: CacheLine);
begin

  -- If invalid move to exclusive
  if(CCEdir[cl].state = I)
  then
    CCEdir[cl].state := E;               -- Change state to exclusive
    CCEdir[cl].owner[lce] := true;       -- mark this lce as an owner
    LCEs[lce][cl].state := E;             -- Change state to exclusive
    LCEs[lce][cl].val := CCEdir[cl].val; -- transfer the value      


  -- If shared keep it shared
  -- Difference here is don't need to update CCE state
  elsif(CCEdir[cl].state = S)
  then
    CCEdir[cl].state := S;               -- Keep the state as shared
    CCEdir[cl].owner[lce] := true;       -- mark this lce as an owner
    LCEs[lce][cl].state := S;            -- Change state to shared
    LCEs[lce][cl].val := CCEdir[cl].val; -- transfer the value      


  -- If exclusive move to shared
  -- Difference here is iterates through list of owners to find and change to shared state
  -- NO WRITEBACK NEEDED IF NO SILENT UPGRADE FROM E TO M
  -- NO MODEL OF CACHE TO CACHE TRANSFER
  elsif(CCEdir[cl].state = E)
  then

    -- iterate through list of owners to find exclusive owner and change it to shared
    for lceiter:LCErange do
      if(CCEdir[cl].owner[lceiter] = true)
      then
        LCEs[lceiter][cl].state := S;    -- Change state of the LCE to shared but keep it as an owner
      endif;
    endfor;

    CCEdir[cl].state := S;               -- Change state to shared
    CCEdir[cl].owner[lce] := true;       -- mark this lce as an owner
    LCEs[lce][cl].state := S;            -- Change state to shared
    LCEs[lce][cl].val := CCEdir[cl].val; -- transfer the value   


  -- If modified, write it back and switch to shared
  -- Difference here is we write back value to CCE
  elsif(CCEdir[cl].state = M)
  then

    -- iterate through list of owners to find exclusive owner and change it to shared
    for lceiter2:LCErange do
      if(CCEdir[cl].owner[lceiter2] = true)
      then
        LCEs[lceiter2][cl].state := S;             -- Change state of the LCE to shared
        CCEdir[cl].val := LCEs[lceiter2][cl].val;  -- Write back modified value  
      endif;
    endfor; 

    CCEdir[cl].state := S;               -- Change state to shared
    CCEdir[cl].owner[lce] := true;       -- mark this lce as an owner
    LCEs[lce][cl].state := S;            -- Change state to shared
    LCEs[lce][cl].val := CCEdir[cl].val; -- transfer the value  

  endif;

end;


procedure WriteReq(lce: LCErange; cl: CacheLine);
begin

  -- If already in modified, write it back and switch to this to invalid but modified for the other
  -- Only difference here is we write back value to CCE
  if(CCEdir[cl].state = M)
  then

    -- iterate through list of owners to find owner and change it to invalid and write back
    for lceiter:LCErange do
      if(CCEdir[cl].owner[lceiter] = true)
      then
        LCEs[lceiter][cl].state := I;             -- Change state of the LCE to invalid
        CCEdir[cl].owner[lceiter] := false;       -- This LCE no longer an owner 
        CCEdir[cl].val := LCEs[lceiter][cl].val;  -- Write back modified value  
      endif;
    endfor; 


  -- For the cacheline existing in any other state do almost same thing minus write back
  else

    -- iterate through list of owners to find owner and change it to invalid
    for lceiter2:LCErange do
      if(CCEdir[cl].owner[lceiter2] = true)
      then
        LCEs[lceiter2][cl].state := I;         -- Change state of the LCE to invalid
        CCEdir[cl].owner[lceiter2] := false;   -- This LCE no longer an owner 
      endif;
    endfor; 

  endif;


  -- both scenarios end in a similar routine which is below
  CCEdir[cl].state := M;               -- Make state modified
  CCEdir[cl].owner[lce] := true;       -- mark this lce as a modifier
  LCEs[lce][cl].state := M;            -- Change state to modified
  LCEs[lce][cl].val := CCEdir[cl].val; -- transfer the value  


end;

-- Iterates through and counts number of sharers
Function NumSharers(cl: CacheLine): LCEcounterRange;
var Count: LCEcounterRange;  -- For counting how many LCE's share possesion
begin
  Count := 0;                -- Initialize to 0

  -- iterate through list of owners to find owner
  for lceiter:LCErange do
    if(CCEdir[cl].owner[lceiter] = true)
    then
      Count := Count + 1; 
    endif;
  endfor; 

  return Count;

end;

procedure Evict(lce: LCErange; cl: CacheLine);
begin

  -- if evicting modified write back
  -- if evicting modified or exclusive change state to invalid
  -- if evicting shared check to see if only 1 set remains if so change to E else keep shared


  -- Evict modified
  if(CCEdir[cl].state = M)
  then
    CCEdir[cl].state := I;                -- Change state to Invalid
    CCEdir[cl].owner[lce] := false;       -- This LCE no longer an owner 
    CCEdir[cl].val := LCEs[lce][cl].val;  -- Write back modified value  
    LCEs[lce][cl].state := I;             -- Change state of the LCE to invalid
    
  -- Evict exclusive
  elsif(CCEdir[cl].state = E)
  then
    CCEdir[cl].state := I;                -- Change state to Invalid
    CCEdir[cl].owner[lce] := false;       -- This LCE no longer an owner  
    LCEs[lce][cl].state := I;             -- Change state of the LCE to invalid


  -- Evict shared
  elsif(CCEdir[cl].state = S)
  then
    CCEdir[cl].owner[lce] := false;       -- This LCE no longer an owner 
    LCEs[lce][cl].state := I;             -- Change state of the LCE to invalid

    -- iterate through list of owners to find owner and change it to either exclusive or shared
    for lceiter:LCErange do
      if(CCEdir[cl].owner[lceiter] = true)
      then
        if(NumSharers(cl) = 1)
        then
          CCEdir[cl].state := E;                -- Change state to exclusive
          LCEs[lceiter][cl].state := E;         -- Change state of the LCE to exculsive since only one left
        else
          CCEdir[cl].state := S;                -- Keep state as shared
          LCEs[lceiter][cl].state := S;         -- Change state of the LCE to sharer since others have copy
        endif;    
      endif;
    endfor; 

  endif;

end;


-- Iterates through and checks if CCE val matches owner vals
-- Note, this could return false when comparing against a modified line
Function OwnerVsCCE(cl: CacheLine): boolean;
begin

  -- iterate through list of owners to find owner
  for lceiter:LCErange do
    if(CCEdir[cl].owner[lceiter] = true)
    then
      -- If an owner's value is not equal then return false
      if(CCEdir[cl].val != LCEs[lceiter][cl].val)
      then
        return false;
      endif;

    endif;
  endfor; 

  -- If all owners equal CCE valus then return true
  return true;

end;

----------------------------------------------------------------------
-- Startstate - Function run to initialize system
----------------------------------------------------------------------
startstate

  -- CCE directory initialization 
  for cl:CacheLine do
    CCEdir[cl].state     := I;       -- Initially invalid state
    CCEdir[cl].val       := 0;       -- Initially 0 and adds each modification
    CCEdir[cl].pending   := false;   -- Initially the cacheline is not pending
    
    for lce:LCErange do
      CCEdir[cl].owner[lce] := false;   -- Initially no one owns a copy
    endfor;

  endfor;

  -- LCEs initializations
  for lce:LCErange do
    for cl:CacheLine do
      LCEs[lce][cl].state      := I;      -- Initially invalid state
      LCEs[lce][cl].val        := 0;      -- Initially 0 and adds each modification
      LCEs[lce][cl].blocking   := false;  -- Initially not blocking
      LCEs[lce][cl].blockd_req := N;      -- There is no blocked request
    endfor;
  endfor;

endstartstate;

----------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------

-- LCE actions (affecting coherency)
-- So if the LCE went S->M it doesn't assign a value in M

--everytime it modifies update value

ruleset lce:LCErange Do
    ruleset cl:CacheLine Do

      -- The equivelent of grabbing request from the pending queue after pending removed from the perspective of the CCE
      -- blocking plays in
      rule "read request"
        ((LCEs[lce][cl].state = I) & (LCEs[lce][cl].blocking = false))
        ==>
        -- If pending go into blocking mode
        if(CCEdir[cl].pending = true)
        then
          -- Go into a blocking state, store blocked request type
          LCEs[lce][cl].blocking   := true;
          LCEs[lce][cl].blockd_req := R;
        else
          ReadReq(lce, cl);   -- Handles all read requests
        endif;
      endrule;

      -- The equivelent of grabbing request from the pending queue after pending removed from the perspective of the CCE
      -- blocking plays in
      rule "write request"
        (((LCEs[lce][cl].state = I) | (LCEs[lce][cl].state = E) | (LCEs[lce][cl].state = S)) & (LCEs[lce][cl].blocking = false))        
        ==>
        -- If pending go into blocking mode
        if(CCEdir[cl].pending = true)
        then
          -- Go into a blocking state
          LCEs[lce][cl].blocking   := true;
          LCEs[lce][cl].blockd_req := W;
        else
          WriteReq(lce, cl);  -- Handles all write requests
        endif;
      endrule;

      -- Pending bits don't really apply to evicting unmodified lines but since CCE handles eviction through the LCE blocking does play in
      rule "evict unmodified"
        (((LCEs[lce][cl].state = E) | (LCEs[lce][cl].state = S)) & (LCEs[lce][cl].blocking = false))
        ==>
        Evict(lce, cl);     -- Handles all eviction req
      endrule;

      -- Pending bits and blocking apply to evicting modified lines due to writeback
      rule "evict modified"
        ((LCEs[lce][cl].state = M) & (LCEs[lce][cl].blocking = false))
        ==>
        -- If pending go into blocking mode
        if(CCEdir[cl].pending = true)
        then
          -- Go into a blocking state
          LCEs[lce][cl].blocking   := true;
          LCEs[lce][cl].blockd_req := EM;
        else
          Evict(lce, cl);     -- Handles all eviction req
        endif;
      endrule;
        
      
      -- Since this is a write hit operation, the LCE blocking doesn't effect it
      -- LCE holds write priviledge, then write to line
      -- The writen value here can be different from CCE value till writeback since not write through
      -- Incrementing is an arbitrary way of assigning value while also being a useful indicator 
      -- for validating coherence
      rule "store new value to line"
        (LCEs[lce][cl].state = M)
        ==>
        LCEs[lce][cl].val := LCEs[lce][cl].val + 1;   
      endrule;


      -- CCE changing cacheline to pending if it wasn't
      -- Used to create pending states generated by other LCEs or even this one itself
      rule "Cacheline starts pending"
        (CCEdir[cl].pending = false)
        ==>
        CCEdir[cl].pending := true;
      endrule;

      -- Actually uses a fifo, but no need to impliment a fifo just treat this pending op as
      -- a signal to the LCE that the time to perform its blocked op is now
      rule "Cacheline done pending"
        (CCEdir[cl].pending = true)
        ==>
        CCEdir[cl].pending := false;      -- clear pending bit
        LCEs[lce][cl].blocking := false;  -- remove blocking property if it was applied

        -- Execute pending operation if it was previously blocking
        if(LCEs[lce][cl].blockd_req = W)
        then
          -- Executes pending write req
          WriteReq(lce, cl); 
        elsif(LCEs[lce][cl].blockd_req = R)
        then
          -- Executes pending read req
          ReadReq(lce, cl);
        elsif(LCEs[lce][cl].blockd_req = EM)
        then
          -- Executes pending eviction req
          Evict(lce, cl);    
        endif;

        -- Change blocked request type to N for none
        LCEs[lce][cl].blockd_req := N;

      endrule;


    endruleset;
endruleset;
----------------------------------------------------------------------
-- Invariants
----------------------------------------------------------------------

-- For some reason, when doing a for all, you don't end with an end for
-- and you leave off the semi colon of the -> (expression)
invariant "Invalid implies no owner"
  forall cl:CacheLine  Do
    (CCEdir[cl].state = I)
    ->
      NumSharers(cl) = 0
end;

invariant "Modified or exclusive implies single owner"
  forall cl:CacheLine Do
    (CCEdir[cl].state = M | CCEdir[cl].state = E)
    ->
      NumSharers(cl) = 1
end;

invariant "Shared implies more than 1 owner"
  forall cl:CacheLine Do
    (CCEdir[cl].state = S)
    ->
      NumSharers(cl) > 1
end;

invariant "All values in shared or exclusive state match CCE value and thus eachother"
  forall cl:CacheLine Do
    (CCEdir[cl].state = S | CCEdir[cl].state = E)
    ->
      OwnerVsCCE(cl) = true
end;

invariant "LCEs that are blocking cannot have a request type N"
  forall cl:CacheLine Do
    forall lce:LCErange Do
      (LCEs[lce][cl].blocking = true)
      ->
      LCEs[lce][cl].blockd_req != N
    end
end;
