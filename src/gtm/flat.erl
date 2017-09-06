%%
%% Created flat.erl the 08:25:49 (01/08/2017) on core
%% Last Modification of flat.erl at 09:32:07 (04/08/2017) on core
%% 
%% @author ak <ak@harmonygroup.net>
%% @doc Description.
%%

-module(flat).

-define(debug, true).

-ifdef(debug).
-export([ test/0 ]).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

-export([
    unpack/1
]).

unpack(Data) ->
    unpack(Data, 0, []).

unpack(<<":[",Data/binary>>, 0, Result) ->
    case readsize(Data) of
        false ->
            {error, badarg};

        {Size, Rest} ->
            readlist(Size, Result, Rest)
    end;

%unpack(<<"^",Data/binary>>, Size, Result) ->
%    readitem(Data,
    
unpack(Data, Size, Result) ->
    ?DEBUG("Size: ~p: Result: ~p", [ Size, Result ]).

readlist(Count, Result, Data) ->
    ?DEBUG("Readlist: Count: ~p", [ Count ]),
    case readitem(Data, Count, undefined, []) of
        false ->
            {error, badarg};

        {Item, Rest} ->
            unpack(Rest, 0, [ Item | Result ])
    end.
    

readsize(Data) ->
    case binary:split(Data,<<":">>) of
       [ Size, Rest ] ->
            ?DEBUG("\nSize: ~p: Rest: ~p", [ Size, Rest ]),
            {binary_to_integer(Size), Rest};

        _ ->
            false
    end.

readitem(Data, 0, _, Result) ->
    case binary:split(Data,<<"]">>) of
        [Value, Rest] ->
            ?DEBUG("\nCount: 0, Item: ~p: Rest: ~p", [ Value, Rest ]),
            {[ Value | Result], Rest };
        
        _ ->
            false
    end;
readitem(<<"^",Data/binary>>, Count, undefined, Result) ->
    case binary:split(Data,<<"^">>) of
        [Item, Rest] ->
            ?DEBUG("\nCount: ~p, Item: ~p: Rest: ~p", [ Count, Item, Rest ]),
            readitem(Rest, Count, Item, Result);

        _ ->
            false
    end;
readitem(<<":[",Data/binary>>, Count, Key, Result) ->
    case readsize(Data) of
        false ->
            {error, badarg};

        {Size, Rest} ->
            readlist(Size, [ Key | Result ], Rest)
    end;
readitem(Data, Count, Key, Result) ->
    case binary:split(Data,<<"^">>) of
        [Value, Rest] ->
            ?DEBUG("\nCount: ~p, Item: ~p: Rest: ~p", [ Count, Value, Rest ]),
            readitem(Rest, Count - 1, undefined, [ {Key, Value} | Result ]);

        _ ->
            false
    end.
        

test() ->
    Data = <<":[2:^0^:[7:^activity^:[2:^likes^1^rate^5]^api^:[2:^id^123DvVkKpgUHYmMGrdE4p64221I60441^type^app]^author^:[3:^avatar^^hid^^sex^]^info^:[11:^author^123^avatar^http://cdn.harmony-dev.com/harmony-zfmvaiwqnj.png^bundle^com.harmony.zfmvaiwqnj^category^store^datetime^1477846041^description^New version of zfmvaiwqnj !^parent^?00054123GGW51j4CNBoHxwF8or64221U61378^rating^5^screenshots^0^title^Harmonyzfmvaiwqnj^usersCount^0]^options^:[3:^commentflag^1^rateflag^1^shareflag^1]^source^:[4:^author^123^avatar^http://cdn.harmony-dev.com/harmony-drjmoeqihi.png^datetime^1477846978^title^]^stats^:[1:^likes^1]]^1^:[7:^activity^:[2:^likes^1^rate^5]^api^:[2:^id^173eUnhEFCOWwGMgPktbE64221S57743^type^testimonial]^author^:[3:^avatar^^hid^^sex^]^info^:[11:^author^173^avatar^http://cdn.harmony-dev.com/harmony-zfmvaiwqnj.png^bundle^com.harmony.zfmvaiwqnj^category^store^datetime^1477843343^description^Description^parent^%00054123RnvBkq1LeLxZ38Q64864221P57743^rating^5^screenshots^0^title^Title^usersCount^0]^options^:[3:^commentflag^1^rateflag^1^shareflag^1]^source^:[4:^author^123^avatar^http://cdn.harmony-dev.com/harmony-sl5vgg9wb2.png^datetime^1477843343^title^]^stats^:[1:^likes^1]]]">>,
    unpack(Data).

