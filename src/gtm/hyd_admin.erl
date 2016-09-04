-module(hyd_admin).
% Created hyd_admin.erl the 06:31:48 (07/02/2016) on core
% Last Modification of hyd_admin.erl at 23:31:52 (08/03/2016) on sd-19230
% 
% Author: "ak" <ak@harmonygroup.net>

-export([
    reload/0
]).

-export([
    get_for/3,
    get_labels/2,
    get_value/3,
    set_value/4,
    set_label/5,
    set_value/5,
    set_value/6,
    add_value/4,
    get_address/3,
    new_multiple/3,
    get_addresses/2,
    set_visibility/5,
    get_address_for/4,
    set_address_value/5,
    set_address_title/4,
    get_addresses_for/3,
    set_visibility_tmp/6
]).

-export([
    cancel/2,
    validate/2,
    contract/5,
    set_value_tmp/6,
    set_label_tmp/6,
    set_own_value_tmp/6,
    set_own_value_tmp/7,
    set_own_label_tmp/7,
    set_address_value_tmp/6,
    set_address_title_tmp/5
]).

-export([
    get_own_value/3, 
    get_own_value/4,
    set_own_label/6,
    add_own_value/5,
    get_own_address/4,
    new_own_multiple/4,
    get_own_addresses/3,
    set_own_address_value/6,
    set_own_address_title/5
]).

-export([
    create_user/5
]).

admintree() ->
    <<"admintree">>.

reload() ->
    hyd:reload( admintree()  ).

get_for(Userid, Relation, Section) ->
    Ops = [
        hyd:operation(<<"getFor">>, admintree(), [ Userid, Relation, Section ])
    ],
    run(Ops).

get_address_for(Userid, Relation, Section, Index) ->
    Ops = [
        hyd:operation(<<"getAddressFor">>, admintree(), [ Userid, Relation, Section, Index ])
    ],
    run(Ops).

set_visibility(Userid, Key, Field, Index, Visibility) ->
    Filtered = quote(Visibility),
    Ops = [
        hyd:operation(<<"setVisibility">>, admintree(), [ Userid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

set_visibility_tmp(Userid, Key, Field, Index, Visibility, Tmp) ->
    Filtered = quote(Visibility),
    Ops = [
        hyd:operation(<<"setVisibility">>, admintree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

new_multiple(Userid, Key, Type) ->
    Ops = [
        hyd:operation(<<"newMultiple">>, admintree(), [ Userid, Key, Type ])
    ],
    run(Ops).

new_own_multiple(Userid, Contactid, Key, Type) ->
    Ops = [
        hyd:operation(<<"newOwnMultiple">>, admintree(), [ Userid, Contactid, Key, Type ])
    ],
    run(Ops).
    
add_value(Userid, Key, Subkey, Value) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"add">>, admintree(), [ Userid, Key, Subkey, Filtered ])
    ],
    run(Ops).

add_own_value(Userid, Contactid, Key, Subkey, Value) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"addOwn">>, admintree(), [ Userid, Contactid, Key, Subkey, Filtered ])
    ],
    run(Ops).


set_value(Adminid, Userid, Key, Values) when is_list(Values) ->
    lists:foldl( fun
        (_, {error, _} = Error) ->
            Error;
            
        ({K,V}, Acc) ->
            %[ Index ] = add_value(Userid, Key, K, V),
            case add_value(Userid, Key, K, V) of
                [ Index ] ->
                    [ {K, Index} | Acc ];
                {error, _} = Error ->
                    Error
                    %[ Error | Acc ]
            end;

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                add_value(Userid, Key, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values).

set_value(Adminid, Userid, Key, Values, Field) when is_list(Values) ;
    Field =:= <<"address">> ->
    case new_multiple(Userid, Key, Field) of
        {error, _} = Err ->
            Err;

        [Index] ->
            set_value(Userid, Key, Values, Field, Index),
            Index
    end.

set_value(Adminid, Userid, Key, Values, <<"address">>, Index) when is_list(Values) ->
    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            set_address_title(Userid, Key, Index, V);

        ({K,V}, _Acc) ->
            set_address_value(Userid, Key, Index, K, V);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                set_address_value(Userid, Key, Index, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

set_value(Admin, Userid, Key, Value, Field, Index) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"set">>, admintree(), [ Userid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

set_label(Adminid, Key, Field, Index, Label) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setLabel">>, admintree(), [ Adminid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

set_own_label(Userid, Contactid, Key, Field, Index, Label) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setOwnLabel">>, admintree(), [ Userid, Contactid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

% set_value(Userid, Key, Value) ->
%     add_value(Userid, Key, Value, []).

get_value(Userid, Id, Key) ->
    Ops = [
        hyd:operation(<<"get">>, admintree(), [ Userid, Id, Key ])
    ],
    run(Ops).

get_own_value(Userid, Contactid, Key) ->
    Ops = [
        hyd:operation(<<"getOwn">>, admintree(), [ Userid, Contactid, Key ])
    ],
    run(Ops).

get_value(Userid, Id, Key, Subkey) ->
    Ops = [
        hyd:operation(<<"get">>, admintree(), [ Userid, Id, Key, Subkey ])
    ],
    run(Ops).

get_own_value(Userid, Contactid, Key, Subkey) ->
    Ops = [
        hyd:operation(<<"getOwn">>, admintree(), [ Userid, Contactid, Key, Subkey ])
    ],
    run(Ops).

get_labels(Category, Field) ->
    Ops = [
        hyd:operation(<<"getLabels">>, admintree(), [ Category, Field ])
    ],
    run(Ops).

% get_addresses(Userid,Category) ->
%     Ops = [
%         hyd:operation(<<"getAddresses">>, admintree(), [ Userid, Category ])
%     ],
%     case run(Ops) of
%         [] ->
%             [];
% 
%         Indexes ->
%             lists:foldl( fun(Index, Acc) ->
%                 [ Addr ] = get_address(Userid,Category,Index),
%                 [ Addr | Acc ]
%             end, [], Indexes)
%     end.

get_addresses(Userid,Category) ->
    Ops = [
        hyd:operation(<<"getAddresses">>, admintree(), [ Userid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index, Acc) ->
                case get_address(Userid,Category,Index) of
                    [] ->
                        Acc;
                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

get_addresses_for(Userid, Relation, Category) ->
    Ops = [
        hyd:operation(<<"getAddresses">>, admintree(), [ Userid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index, Acc) ->
                case get_address_for(Userid, Relation, Category, Index) of
                    [] ->
                        Acc;

                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

get_own_addresses(Userid,Contactid,Category) ->
    Ops = [
        hyd:operation(<<"getOwnAddresses">>, admintree(), [ Userid, Contactid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index,Acc) ->
                case get_own_address(Userid,Contactid,Category,Index) of
                    [] ->
                        Acc;
                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

get_address(Userid,Category,Index) ->
    Ops = [
        hyd:operation(<<"getAddress">>, admintree(), [ Userid, Category, Index ])
    ],
    run(Ops).

get_own_address(Userid,Contactid,Category,Index) ->
    Ops = [
        hyd:operation(<<"getOwnAddress">>, admintree(), [ Userid, Contactid, Category, Index ])
    ],
    run(Ops).

set_address_value(Userid, Category, Index, Key, Value) ->
    Ops = [
        hyd:operation(<<"setAddressValue">>, admintree(), [ Userid, Category, Index, Key, quote(Value) ])
    ],
    run(Ops).

set_own_address_value(Userid,Contactid,Category,Index,Key,Value) ->
    Ops = [
        hyd:operation(<<"setOwnAddressValue">>, admintree(), [ Userid, Contactid, Category, Index, Key, quote(Value) ])
    ],
    run(Ops).

set_address_title(Userid,Category,Index,Title) ->
    Ops = [
        hyd:operation(<<"setAddressTitle">>, admintree(), [ Userid, Category, Index, quote(Title) ])
    ],
    run(Ops).

set_own_address_title(Userid,Contactid,Category,Index,Title) ->
    Ops = [
        hyd:operation(<<"setOwnAddressTitle">>, admintree(), [ Userid, Contactid, Category, Index, quote(Title) ])
    ],
    run(Ops).

% Using temporary storage, validate it or cancel it
set_value_tmp(Userid, Key, Values, Field, Index, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->
    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            set_address_title_tmp(Userid, Key, Index, V, Tmp);

        ({K,V}, _Acc) ->
            set_address_value_tmp(Userid, Key, Index, K, V, Tmp);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                set_address_value_tmp(Userid, Key, Index, K, V, Tmp)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

set_value_tmp(Userid, Key, Value, Field, Index, Tmp) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"set">>, admintree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

set_address_value_tmp(Userid, Category, Index, Key, Value, Tmp) ->
    Ops = [
        hyd:operation(<<"setAddressValue">>, admintree(), [ Userid, Category, Index, Key, quote(Value), Tmp ])
    ],
    run(Ops).

set_address_title_tmp(Userid, Category, Index, Title, Tmp) ->
    Ops = [
        hyd:operation(<<"setAddressTitle">>, admintree(), [ Userid, Category, Index, quote(Title), Tmp ])
    ],
    run(Ops).

set_own_value_tmp(Userid, Contactid, Key, Values, Field, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->
    case new_own_multiple(Userid, Contactid, Key, Field) of
        {error, _} = Err ->
            Err;

        [Index] ->
            set_own_value_tmp(Userid, Contactid, Key, Values, Field, Index, Tmp),
            Index
    end.

set_own_value_tmp(Userid, Contactid, Key, Values, Field, Index, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->

    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            set_own_address_title_tmp(Userid, Contactid, Key, Index, V, Tmp);

        ({K,V}, _Acc) ->
            set_own_address_value_tmp(Userid, Contactid, Key, Index, K, V, Tmp);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                set_own_address_value_tmp(Userid, Contactid, Key, Index, K, V, Tmp)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

set_own_value_tmp(Userid, Contactid, Key, Value, Field, Index, Tmp) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"setOwn">>, admintree(), [ Userid, Contactid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

set_label_tmp(Userid, Key, Field, Index, Label, Tmp) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setLabel">>, admintree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

set_own_label_tmp(Userid, Contactid, Key, Field, Index, Label, Tmp) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setOwnLabel">>, admintree(), [ Userid, Contactid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

set_own_address_value_tmp(Userid, Contactid, Category, Index, Key, Value, Tmp) ->
    Ops = [
        hyd:operation(<<"setOwnAddressValue">>, admintree(), [ Userid, Contactid, Category, Index, Key, quote(Value), Tmp ])
    ],
    run(Ops).

set_own_address_title_tmp(Userid, Contactid, Category, Index, Title, Tmp) ->
    Ops = [
        hyd:operation(<<"setOwnAddressTitle">>, admintree(), [ Userid, Contactid, Category, Index, quote(Title), Tmp ])
    ],
    run(Ops).

cancel(Userid, Tmp) ->
    Ops = [
        hyd:operation(<<"cancel">>, admintree(), [ Userid, Tmp ])
    ],
    run(Ops).

validate(Userid, Tmp) ->
    Ops = [
        hyd:operation(<<"validate">>, admintree(), [ Userid, Tmp ])
    ],
    run(Ops).

contract(Userid, Tmp, Category, Field, Index) ->
    Ops = [
        hyd:operation(<<"contract">>, admintree(), [ Userid, Tmp, Category, Field, Index ])
    ],
    run(Ops).

%% not_implemented() ->
%%     <<"404 Not Implemented">>.

% Safety first
quote(true) -> <<"true">>;
quote(false) -> <<"false">>;
quote(Value) when is_binary(Value) ->
    binary:replace(Value, <<"\"">>, <<31>>, [global]);
quote(Value) when is_integer(Value) ->
    Value.

internal_error(Code) ->
    hyd:error(?MODULE, Code).

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

run(Op) ->
    hyd:run(Op).

create_user(Adminid, Userid, Firstname, Lastname, Domain) ->
    Ops = [
        hyd:operation(<<"createUser">>, admintree(), [ Adminid, quote(Userid), quote(Firstname), quote(Lastname), quote(Domain) ])
    ],
    run(Ops).

