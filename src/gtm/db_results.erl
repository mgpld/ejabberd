-module(db_results).
% Created db_results.erl the 12:24:07 (27/05/2014) on core
% Last Modification of db_results.erl at 23:16:44 (30/08/2016) on core
% 
% Author: "rolph" <rolphin@free.fr>

-define(debug, true).

-ifdef(debug).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

-export([
    unpack/1
]).

% handling success or failures from the store
unpack(Bool) when
    Bool =:= true;
    Bool =:= false ->
    {ok, Bool};

unpack(Data) ->
    %%?DEBUG(" -- Unpack --( ~p bytes )\n~p\n", [ iolist_size(Data), Data ]),
    ?DEBUG(" -- Unpack --( ~p bytes )", [ iolist_size(Data) ]),
    unpack(Data, undefined, []).

% Informational Errors
unpack(<<Count:16,0,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed error: ~p", [ Count ]),
    unpack(0, Rest, Count, Result);

% Simple list
unpack(<<Count:16,1,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed simple-list: ~p", [ Count ]),
    unpack(1, Rest, Count, Result);

% List of key/values
unpack(<<Count:16,2,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed list-key-value: ~p", [ Count ]),
    unpack(2, Rest, Count, Result);

% List of List of Key/Values
unpack(<<Count:16,3,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed list-of-list-key-value: ~p", [ Count ]),
    unpack(3, Rest, Count, Result);

% List of List of Key, SubKey/Values
unpack(<<Count:16,4,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed list-of-list-key-subkey-value: ~p", [ Count ]),
    unpack(4, Rest, Count, Result);

unpack(<<Count:16,9,Rest/binary>>, undefined, Result) ->
    ?DEBUG("Packed internal list-of-key-value: ~p", [ Count ]),
    unpack(9, Rest, Count, Result);

% fallback to return small _anything_ data from the store
unpack( Data, _, _) when byte_size(Data) < 128 ->
    {ok, Data};

unpack(_Data, undefined, _Result) ->
    ?DEBUG("Packet unknown: ~p\n", [ _Data ]),
    {error, badarg}.
    

% Type: 0 Error
unpack(0, <<KS:16,Key:KS/binary,VS:16,Value:VS/binary,Rest/binary>>, Count, Result) ->
    unpack(0, Rest, Count - 1, [ {Key, Value} | Result]);

% Type: 1 Key
unpack(1, <<KS:16,Key:KS/binary,Rest/binary>>, Count, Result) ->
    unpack(1, Rest, Count - 1, [ Key | Result ]);

% Type: 2 Key Value
unpack(2, <<KS:16,Key:KS/binary,VS:16,Value:VS/binary,Rest/binary>>, Count, Result) ->
    unpack(2, Rest, Count - 1, [ {Key, hyd:unquote(Value)} | Result]);

% Type: 3 Multiple Key Value
unpack(3, <<IndexCount:16,Rest/binary>>, Count, Result) ->
    {NewResult, NewRest} = unpack_values(IndexCount, Rest, Result),
    unpack(3, NewRest, Count - 1, NewResult);

% Type: 4 Multiple Key Subkey Value
%unpack(4, <<IndexCount:16,Rest/binary>>, Count, Result) ->
unpack(4, Rest, Count, Result) ->
    ?DEBUG("list-of-list-key-subkey-value: count ~p", [ Count ]),
    %{NewResult, NewRest} = unpack_key(undefined, Rest, Result),
    unpack_key(undefined, Rest, Result);
    %unpack(4, NewRest, Count - 1, NewResult);
    

% Type: 9 internal information
unpack(9, Rest, 0, Result) ->
    {ok, Result, Rest};

unpack(9, <<Type:8,VS:16,Value:VS/binary,Rest/binary>>, Count, Result) ->
    ?DEBUG("Packed internal ~p key-value: ~p ~p", [ Count, Type, Value ]),
    unpack(9, Rest, Count - 1, [{Type, Value} | Result]);
    
unpack(0, <<>>, _Count, Result) ->
    {error, Result}; 

unpack(_, <<>>, 0, Result) ->
    {ok, Result};

unpack(_, <<>>, _Count, Result) ->
    {ok, Result}.


unpack_values(0, Rest, Result) ->
    {Result, Rest};
unpack_values(Count, <<IS:16,Index:IS/binary,Rest/binary>>,  Result) ->
    ?DEBUG("index: ~p, subelements count: ~p", [ Index, Count ]),
    { NewResult, NewRest} = extract_values(Count, Rest, []),
    {[ { Index, NewResult } | Result ], NewRest};
unpack_values(_Count, <<>> = Rest, Result) ->
    {Result, Rest}. 

unpack_key(_, <<>>, Result) ->
    {ok, Result};
unpack_key(undefined, <<Count:16,KS:16,Key:KS/binary,SubCount:16,Rest/binary>>, Result) ->
    ?DEBUG("Root key: ~p, ~p", [ Key, Count ]),
    { NewResult, NewRest } = unpack_subkey(SubCount, Rest, Result, Key),
    %?DEBUG("NewRest: ~p", [ NewRest ]),
    unpack_next(Count - 1, NewRest, [ NewResult | Result ], Key, []).
    %unpack_next(Count - 1, NewRest, [ {Key, NewResult} | Result ], Key, []).

unpack_next(0, Rest, Result, Key, TmpResult) ->
    ?DEBUG("unpack_next: end", []),
    %?DEBUG("unpack_next: Key: ~p Result: ~p", [Key, Result]),
    unpack_key(undefined, Rest, [ {Key, TmpResult} | Result ]);
unpack_next(_, <<>>, Result, _, _) ->
    {ok, Result};
unpack_next(Count, <<SubCount:16,Rest/binary>>, Result, Key, TmpResult) ->
    ?DEBUG("unpack_next: count ~p", [ Count ]),
    %?DEBUG("unpack_next: Key: ~p Result: ~p", [Key, Result]),
    { NewResult, NewRest } = unpack_subkey(SubCount, Rest, Result, Key),
    unpack_next(Count - 1, NewRest, Result, Key, [ NewResult | TmpResult ]).
    %unpack_next(Count - 1, NewRest, [ {Key, NewResult} | Result ], Key, TmpResult).


% unpack_key_subkey_values(0, Rest, Result) ->
%     {Result, Rest};
% unpack_key_subkey_values(Count, <<IndexCount:16,IS:16,Index:IS/binary,SubCount:16,SIS:16,SubIndex:SIS/binary,Rest/binary>>, Result) ->
% %unpack_key_subkey_values(Count, <<IS:16,Index:IS/binary,SubCount:16,Rest/binary>>, Result) ->
%     ?DEBUG("Rest: ~p", [ Rest ]),
%     ?DEBUG("1 count: ~p index: ~p, sub-count: ~p" , [ IndexCount, Index, SubCount ]),
%     { NewResult, NewRest } = unpack_subkey(SubCount, Rest, Result, Index),
%     ?DEBUG("NewRest: ~p", [ NewRest ]),
%     unpack_key_subkey_values( Count - 1, NewRest, NewResult);
% 
% unpack_key_subkey_values(Count, <<IndexCount:16,IS:16,Index:IS/binary,SubCount:16,SIS:16,SubIndex:SIS/binary,Rest/binary>>, Result) ->
%     ?DEBUG("Rest: ~p", [ Rest ]),
%     ?DEBUG("f count: ~p index: ~p, sub-index: ~p subelements count: ~p", [ Count, Index, SubIndex, SubCount ]),
%     { NewResult, NewRest} = extract_values(SubCount, Rest, []),
%     ?DEBUG("NewRest: ~p", [ NewRest ]),
%     unpack_key_subkey_values(Count - 1, NewRest, [{Index, {SubIndex, NewResult}} | Result]);
%     %{[ { Index, {SubIndex, NewResult} } | Result ], NewRest};
% unpack_key_subkey_values(Count, <<SubCount:16,SIS:16,SubIndex:SIS/binary,Rest/binary>>, Result) ->
%     ?DEBUG("s count: ~p  sub-index: ~p subelements count: ~p", [ Count, SubIndex, SubCount ]),
%     { NewResult, NewRest} = extract_values(SubCount, Rest, []),
%     unpack_key_subkey_values(Count - 1, NewRest, [{SubIndex, NewResult} | Result]);
% unpack_key_subkey_values(_, <<Count:16,Rest/binary>>, Result) ->
%     ?DEBUG("+Rest: ~p", [ Rest ]),
%     unpack_key_subkey_values(Count, Rest, Result);
% 
% unpack_key_subkey_values(_Count, <<>> = Rest, Result) ->
%     {Result, Rest}. 

unpack_subkey(Count, <<SIS:16,SubIndex:SIS/binary,Rest/binary>>, _Result, Index) ->
    ?DEBUG("subkey count: ~p index: ~p, sub-index: ~p" , [ Count, Index, SubIndex ]),
    { Values, NewRest} = extract_values(Count, Rest, []),
    { {SubIndex, Values}, NewRest}.
    

extract_values(0, Rest, Result) ->
    {Result, Rest};
extract_values(Count, <<KS:16,Value:KS/binary,0:16,Rest/binary>>, Result) -> % when value is empty i.e. ""
    ?DEBUG("elem: ~p, Value: ~p", [ Count, Value ]),
    extract_values(Count - 1, Rest, [ {hyd:unquote(Value), <<>>} | Result ]); % unquote the key and set the empty binary <<>> as value
extract_values(Count, <<KS:16,Key:KS/binary,VS:16,Value:VS/binary,Rest/binary>>, Result) ->
    ?DEBUG("elem: ~p, Key: ~p, Value: ~p", [ Count, Key, Value ]),
    extract_values(Count - 1, Rest, [ {Key, hyd:unquote(Value)} | Result ]);
extract_values(_Count, <<>> = Rest, Result) ->
    {Result, Rest}. 
    
