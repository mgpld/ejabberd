-module(hyd_users).
% Created hyd_users.erl the 17:16:36 (12/10/2013) on core
% Last Modification of hyd_users.erl at 12:41:01 (21/11/2016) on core
%
% Author: rolph
% Harmony Data - Users

-define(debug, true).

-ifdef(debug).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

-export([
    all/2,
    foreach/3,
    childs/2, childs/3,
    childs_values/2,
    add_sub_element/3,
    del_sub_element/3,
    replace_sub_element/4
]).

-export([
    all_contacts_from_category/2,
    all_specific_properties_from_category/3
]).
-export([
    contacts/1,
    contacts_tree/1,
    contacts_search/2,
    contacts_categories/1,
    contacts_invitations/2,
    contacts_from_category/2,
    contacts_info_from_category/2,
    contacts_info_from_invitations/2,
    userid/3
]).

-export([
    config_all/1,
    config_get_value/2,
    config_set_value/3
]).

-export([
    pages/1,
    groups/1,
    threads/1,
    comgroups/1,
    contactlists/1,
    subscriptions/1
]).

-export([
    reload/0,
    async_run/4
]).

-export([
    profiles/1,
    profile_get/2,
    profile_delete/2,
    profile_set_value/4,
    profile_del_value/3,
    profiles_tree/1, profiles_tree/2
]).

-export([
    presence_get/3,
    presence_set/4,
    presences_tree/1
]).

-export([
    info/1, info/2,
    canonical/1,
    internal/1,
    info_user/2, info_user/3, info_user/4, 
    info_about/2, info_about/3, info_about/4,
    info_contact/3, info_contact/4, info_contact/5,
    info_own_contact/3, info_own_contact/4, info_own_contact/5,
    connected_contacts/2
]).

-export([
    registry_get_value/2, registry_get_value/3,
    registry_set_value/3,
    registry_add_value/4,
    registry_get_old_value/3, registry_get_old_value/4
]).

-export([
    infotree_get_for/3,
    infotree_get_field/2,
    infotree_get_value/2, 
    infotree_get_value/3,
    infotree_set_value/3,
    infotree_set_label/5,
    infotree_set_value/4,
    infotree_set_value/5,
    infotree_add_value/4,
    infotree_get_address/3,
    infotree_new_multiple/3,
    infotree_get_addresses/2,
    infotree_set_visibility/5,
    infotree_get_address_for/4,
    infotree_set_address_value/5,
    infotree_set_address_title/4,
    infotree_get_addresses_for/3,
    infotree_set_visibility_tmp/6
]).

-export([
    infotree_cancel/2,
    infotree_validate/2,
    infotree_contract/5,
    infotree_set_value_tmp/6,
    infotree_set_label_tmp/6,
    infotree_set_own_value_tmp/6,
    infotree_set_own_value_tmp/7,
    infotree_set_own_label_tmp/7,
    infotree_set_address_value_tmp/6,
    infotree_set_address_title_tmp/5
]).

-export([
    infotree_get_own_value/3, 
    infotree_get_own_value/4,
    infotree_set_own_value/4,
    infotree_set_own_value/5,
    infotree_set_own_label/6,
    infotree_set_own_value/6,
    infotree_add_own_value/5,
    infotree_get_own_address/4,
    infotree_new_own_multiple/4,
    infotree_get_own_addresses/3,
    infotree_set_own_address_value/6,
    infotree_set_own_address_title/5
]).

-export([
    delete_info/2, %delete_info/3, delete_info/4,
    delete_own_info/3%, delete_own_info/4, delete_own_info/5
]).

-export([
    add_contact/2,
    list_blocked/1,
    list_blocked/2,
    add_category/2,
    block_contact/2,
    invite_contact/2,
    accept_contact/2,
    refuse_contact/2,
    cancel_contact/2,
    delete_contact/2,
    unblock_contact/2,
    add_contact_in_category/3
]).

-export([
    read/2,
    write/3
]).

-export([
    session_dns/2,
    session_end/2,
    session_new/4,
    session_init/2
]).

-define(ROOT_USER, "^users").
-define(USER_MODULE, <<"users">>).
-define(HIDDEN_PROP, "!").
-define(DATA_PROP, "*").
-define(USER_PROP, "+").
-define(CONF_PROP, "#").
-define(VIEW_PROP, "views").

-define(NONE, <<>>).

module() ->
    <<"users">>.

infotree() ->
    <<"infotree">>.

session() ->
    <<"sessions">>.

reload() ->
    hyd:reload( module()  ).

-spec all( 
    UserId :: non_neg_integer(),
    Subscripts :: list() ) -> list().

all(UserId, Subscripts) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
	    hyd:operation(<<"childs">>, module(), [ UserId, Args ])
    ],
    run(Ops).

childs(UserId,Subscripts) ->
    Fun = fun(X) ->
	    X
    end,
    childs(UserId,Subscripts,Fun).

childs(Root,Subscripts,Fun) ->
    Subs = Subscripts ++ ["items"],
    foreach(Root,Subs,Fun).
    
foreach(UserId,Subscripts,Fun) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
        hyd:operation(<<"childs">>, module(), [ UserId, Args ])
    ],
    case hyd:call(Ops) of
        {ok, [true]} ->
            [];

        {ok, [Result]} ->  % One Op means One result
            %Results = db_results:unpack(Packed),
            case db_results:unpack( Result ) of
                {ok, Elements} ->
                    lists:map( fun(X) ->
                        Fun( X )
                    end, Elements );

                {error, _} = _Err ->
                    _Err
            end;

        [<<"0">>] ->
            [];

        _ ->
            []
    end.

childs_values(UserId, Subscripts) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
	    hyd:operation(<<"childsKV">>, module(), [ UserId, Args ])
    ],
    run(Ops).

add_sub_element(Userid, Category, Item) ->
    Ops = [
        hyd:operation(<<"insertSubElement">>, module(), [ Userid, Category, Item ])
    ],
    run(Ops).

del_sub_element(Userid, Category, Item) ->
    Ops = [
        hyd:operation(<<"removeSubElement">>, module(), [ Userid, Category, Item ])
    ],
    run(Ops).

replace_sub_element(Userid, Category, Item, NewItem) ->
    Ops = [
        hyd:operation(<<"removeSubElement">>, module(), [ Userid, Category, Item, NewItem ])
    ],
    run(Ops).

-spec profiles(
    UserId :: non_neg_integer()) -> list().

profiles(UserId) ->
    all(UserId, [?CONF_PROP,"profiles"]).

-spec profile_get(
    UserId :: non_neg_integer(),
    Profile :: list() | binary()) -> list().

profile_get(_Userid, _Profile) ->
    internal_error(325).
    
-spec profile_set_value(
    Userid :: non_neg_integer(),
    Profile :: list(),
    Key :: list(),
    Value :: list() ) -> ok.

profile_set_value( Userid, Profile, Key, Value ) ->
    %egistry_add_value(Userid, Profile, Key, Value ).
    write(Userid, [?CONF_PROP,"profiles",Profile,Key], Value).

-spec profile_del_value(
    Userid :: non_neg_integer(),
    Profile :: list(),
    Key :: list() ) -> ok.

profile_del_value( Userid, Profile, Key ) ->
    delete(Userid, [?CONF_PROP,"profiles",Profile,Key]).

-spec profile_delete(
    UserId :: non_neg_integer(),
    Value :: list() | binary()) -> ok.

profile_delete(Userid,Value) ->
    delete(Userid, [?CONF_PROP,"profiles",Value]).

profiles_tree(UserId, Key) ->
    Fun = fun(Profile) ->
        %io:format("---> ~p\n", [ Profile ]),
        {Profile, read(UserId, [?CONF_PROP,"profiles",Profile, Key])}
    end,
    foreach(UserId,[?CONF_PROP,"profiles"], Fun).

profiles_tree(UserId) ->
    Fun = fun(Profile) ->
        %io:format("---> ~p\n", [ Profile ]),
        {Profile, childs_values(UserId, [?CONF_PROP,"profiles",Profile])}
    end,
    foreach(UserId,[?CONF_PROP,"profiles"], Fun).

%% Presences
-spec presence_set(
    Userid :: non_neg_integer(),
    Profile :: list() | binary(),
    Category :: list() | binary(),
    Value :: list() | binary()) -> ok.

presence_set( Userid, Profile, Category, Value ) ->
    write(Userid, [?CONF_PROP,"presences", Profile, Category], Value).

-spec presence_get(
    UserId :: non_neg_integer(),
    Profile :: list() | binary(),
    Category :: list() | binary()) -> list().

presence_get(Userid, Profile, Category) ->
    read(Userid, [?CONF_PROP,"presences", Profile, Category]).

-spec presences_tree(
    UserId :: non_neg_integer()) -> list().

presences_tree(Userid) ->
    Fun = fun(Profile) ->
	    {Profile, childs_values(Userid, [?CONF_PROP,"presences",Profile])}
    end,
    foreach(Userid,[?CONF_PROP,"presences"], Fun).

%%     case egtm_util:foreach(Root,[UserId,?CONF_PROP,"profiles"], fun(_,S,A) -> 
%% 		[ list_to_binary(lists:last(S)) | A ] 
%% 	end) of
%% 
%% 	nomatch -> 
%% 	    [];
%% 	{ok, Res} ->
%% 	    Res
%%     end.

% Contacts Categories or Contacts Group
% For one category it should exists one key in the registry
% registy_add_value(Userid, ContactCategory, [{keys,values}....]).
-spec contacts_categories(
    UserId :: non_neg_integer() ) -> list().

contacts_categories(UserId) ->
    childs(UserId, ["contacts","categories"]).

-spec contacts_invitations(
    Userid :: non_neg_integer(),
    Type :: list() | binary()) -> list().

contacts_invitations(Userid, Type) ->
    %childs(Userid, ["contacts","invitations","items",Type]).
    Ops = [
        hyd:operation(<<"listInvitations">>, module(), [ Userid, Type ])
    ],
    run(Ops).

add_contact(UserId,ContactId) ->
    Ops = [
    	hyd:operation(<<"addContact">>, module(), [ UserId, ContactId ])
    ],
    run(Ops).

-spec invite_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

invite_contact(Userid,Contactid) ->
    Ops = [
    	hyd:operation(<<"inviteContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec accept_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

accept_contact(Userid,Contactid) ->
    Ops = [
	    hyd:operation(<<"acceptContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec refuse_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

refuse_contact(Userid,Contactid) ->
    Ops = [
	    hyd:operation(<<"refuseContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec cancel_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

cancel_contact(Userid,Contactid) ->
    Ops = [
	    hyd:operation(<<"cancelContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec block_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

block_contact(Userid,Contactid) ->
    Ops = [
        hyd:operation(<<"blockContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec unblock_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

unblock_contact(Userid,Contactid) ->
    Ops = [
        hyd:operation(<<"unblockContact">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).

-spec delete_contact(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

delete_contact(UserId,ContactId) ->
    Ops = [
        hyd:operation(<<"deleteContact">>, module(), [ UserId, ContactId ])
    ],
    run(Ops).

-spec list_blocked(
    Userid :: non_neg_integer() ) -> list().

list_blocked(Userid) ->
    childs(Userid, ["contacts","blocked"], fun(X) -> contact_info(Userid, X) end).

list_blocked(Userid, Contactid) ->
    case read(Userid, [<<"contacts">>,<<"blocked">>,<<"items">>, Contactid]) of
        [<<>>] ->
            false;
        [_TS] ->
            true
    end. 

-spec delete_info(
    Userid :: non_neg_integer(),
    Params :: list() ) -> list().

delete_info( Userid, Params ) ->
    Ops = [
        hyd:operation(<<"del">>, infotree(), [ Userid | Params ])
    ],
    run(Ops).

-spec delete_own_info(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer(),
    Params :: list() ) -> list().

delete_own_info( Userid, Contactid, Params ) ->
    Ops = [
        hyd:operation(<<"delOwn">>, infotree(), [ Userid, Contactid | Params ])
    ],
    run(Ops).

-spec contacts( 
    Userid :: non_neg_integer() ) -> list().

contacts(UserId) ->
    childs(UserId,["contacts"]).

add_contact_in_category(UserId,ContactId,Category) ->
    Ops = [
        hyd:operation(<<"addContactInCategory">>, module(), [ UserId, ContactId, Category ])
    ],
    run(Ops).
    
% Extracts "visible" informations from the user contacts
all_contacts_from_category(Userid,Category) ->
    Ops = [
        hyd:operation(<<"contactsFromContactlist">>, module(), [ Userid, Category ])
    ],
    run(Ops).

    %all_specific_properties_from_category(UserId, Category, "visible").

all_specific_properties_from_category(UserId, Category, Type) ->
    Fun = fun(X) ->
	io:format("Type: ~p X: ~p\n", [ Type, X ]),
	[{<<"userid">>, X} | info(X, Type)]
    end,
    childs(UserId, ["contacts","categories","items",Category], Fun).

-spec groups(
    Userid :: non_neg_integer() ) -> list().

groups(Userid) ->
    Ops = [
        hyd:operation(<<"getGroups">>, module(), [ Userid ])
    ],
    run(Ops).
    
-spec threads(
    Userid :: non_neg_integer() ) -> list().
    
threads(Userid) ->
    Ops = [
        hyd:operation(<<"getThreads">>, module(), [ Userid ])
    ],
    run(Ops).

-spec contactlists(
    Userid :: non_neg_integer() ) -> list().
    
contactlists(Userid) ->
    Ops = [
        hyd:operation(<<"getContactLists">>, module(), [ Userid ])
    ],
    run(Ops).

pages(Userid) ->
    Ops = [
        hyd:operation(<<"getPages">>, module(), [ Userid ])
    ],
    run(Ops).

subscriptions(Userid) ->
    Ops = [
        hyd:operation(<<"getSubscriptions">>, module(), [ Userid ])
    ],
    run(Ops).

comgroups(Userid) ->
    Ops = [
        hyd:operation(<<"getComGroups">>, module(), [ Userid ])
    ],
    run(Ops).

-spec userid(
    Username :: list() | binary(),
    Domain :: list() | binary(),
    Passord :: list() | binary()) -> list().

userid(Username,Domain,Password) ->
    Ops = [
        hyd:operation(<<"userid">>, module(), [ Username, Domain, Password ])
    ],
    run(Ops).

-spec add_category(
    UserId :: non_neg_integer(),
    Category :: list() | binary() ) -> ok.
add_category(UserId, Category) ->
    Ops = [
        hyd:operation(<<"addCategory">>, module(), [ UserId, Category ])
    ],
    hyd:call(Ops).

-spec contacts_from_category(
    UserId :: non_neg_integer(),
    Category :: list() ) -> list().

contacts_from_category(Userid,Category) ->
    childs(Userid,["contacts","categories","items",Category]).

-spec contacts_info_from_category(
    UserId :: non_neg_integer(),
    Category :: list() ) -> list().

contacts_info_from_category(Userid, Category) ->
    case contacts_from_category(Userid, Category) of
        [] ->
            [];

        [true] ->
            [];

        Contacts ->
            %?DEBUG("contacts_info_from_category: Userid: ~p, Category: ~p\n~p", [ Userid, Category, Contacts ]),
            lists:foldl(fun(Contact, Result) ->
                %case contact_info(Userid, Contact, Category, <<"visible">>) of
                case contact_info(Userid, Contact) of
                    [] ->
                        Result;
                    Values ->
                        [ [ {<<"id">>, Contact}, {<<"category">>, Category} | Values ] | Result ]
                end
            end, [], Contacts)
    end.

-spec contacts_info_from_invitations(
    Userid :: non_neg_integer(),
    Type :: list() | binary() ) -> list().

contacts_info_from_invitations(Userid,Type) ->
    case contacts_invitations(Userid, Type) of
        [] ->
            [];

        [true] ->
            [];

	    Contacts ->
            lists:foldl(fun({Contact, Date}, Result) ->
                %case info(Contact, <<"visible">>) of
                case canonical(Contact) of
                    [] ->
                        Result;
                    [true] ->
                        Result;

                    Values ->
                       [ [ {<<"id">>, Contact}, {<<"timestamp">>, Date} | Values ] | Result ]
                end
            end, [], Contacts)
    end.

-spec contacts_search(
    UserId :: non_neg_integer(),
    Motif :: list() ) -> list().

contacts_search(Userid, Motif) ->
    Ops = [
        hyd:operation(<<"contactsSearch">>, module(), [ Userid, Motif ])
    ],
    run(Ops).

% Retrieve canonical values for any user
-spec canonical(
    Userid :: non_neg_integer() ) -> list().

canonical(Userid) ->
    Ops = [
        hyd:operation(<<"canonical">>, infotree(), [ Userid ])
    ],
    run(Ops).

% Retreive internal value for any user
% Informations to the user himself at the login time
-spec internal(
    Userid :: non_neg_integer() ) -> list().

internal(Userid) ->
    Ops = [
        hyd:operation(<<"internal">>, infotree(), [ Userid ])
    ],
    run(Ops).

-spec info(
    UserId :: non_neg_integer(),
    Type :: list() | undefined ) -> list().

% returns internal informations 
info(Userid) ->
    info(Userid, undefined).

info(Userid, undefined) ->
    Ops = [
        hyd:operation(<<"info">>, module(), [ Userid ])
    ],
    run(Ops);

% returns information available for a specific type i.e.: "visible"
info(Userid,Type) ->
    Ops = [
        hyd:operation(<<"conditionInfo">>, module(), [ Userid, Type ])
    ],
    run(Ops).

contact_info(Userid, Contactid) ->
    Ops = [
         hyd:operation(<<"contactInfo">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).
 
run(Op) ->
    case hyd:call(Op) of
        {ok, Elements } ->
            ?DEBUG("\nOp: ~p\nResponse: ~p\n\n", [ Op, Elements ]),
            
            case lists:foldl( fun
                (_, {error, _} = _Acc) ->
                    _Acc;
                ({error, _} = _Error, _) ->
                    _Error;
                % (true, Acc) ->
                %     [ true | Acc];
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];
                        {error, _} = Error ->
                            Error
                    end
                end, [], Elements) of

                    {error, _} = Error ->
                        Error;

                    Results when is_list(Results) ->
                        lists:flatten(Results)
                end;
            
        _ ->
            internal_error(833, Op)
    end.

% % returns information about otherid
% % result depends on which otherid's category the userid is 
% % if otherid is nowhere in userid then fallback to property "visible"
% -spec info_user(
%     UserId :: non_neg_integer(), 
%     OtherId :: non_neg_integer()) -> list().
% 
% info_user(UserId, OtherId) ->
%     Ops = [
% 	hyd:operation(<<"viewinfo">>, module(), [ UserId, OtherId ])
%     ], 
%     run(Ops).

% Retrieving informations for the user
-spec info_user(
    UserId :: non_neg_integer(), 
    Section :: list() | binary() ) -> list().

info_user(Userid, Section) ->
    infotree_get_value(Userid, Section).

-spec info_user( 
    Userid :: non_neg_integer(), 
    Section :: list() | binary(),
    Field :: list() | binary()) -> list().

info_user(Userid, Section, <<"addresses">>) ->
    infotree_get_addresses(Userid, Section);
    
info_user(_Userid, _Section, _) ->
    [].

-spec info_user( 
    Userid :: non_neg_integer(), 
    Section :: list() | binary(), 
    Field :: list() | binary(),
    Index :: non_neg_integer()) -> list().

info_user(Userid, Section, <<"address">>, Index) ->
    infotree_get_address(Userid, Section, Index);

info_user(_Userid, _Section, _, _) ->
    [].


% Retrieving information for a contact (OtherId)
-spec info_contact(
    Userid :: non_neg_integer(),
    Otherid :: non_neg_integer(),
    Section :: list() | binary() ) -> list().

info_contact(Userid, Contactid, Section) ->
    case connected_contacts(Userid, Contactid) of
        [] ->
            [];
        
        [true] ->
            [];

        [_Timestamp] ->
            infotree_get_value(Contactid, Section)
    end.

info_contact(Userid, Contactid, Section, <<"addresses">>) ->
    case connected_contacts(Userid, Contactid) of
        [] ->
            [];

        [true] ->
            [];

        [_Timestamp] ->
            infotree_get_addresses(Contactid, Section)
    end;
    
info_contact(_Userid, _Contactid, _Section, _) ->
    [].

info_contact(Userid, Contactid, Section, <<"address">>, Index) ->
    case connected_contacts(Userid, Contactid) of
        [] ->
            [];

        [true] ->
            [];

        [_Timestamp] ->
            infotree_get_address(Contactid, Section, Index)
    end;

info_contact(_Userid, _Contactid, _Section, _, _) ->
    [].

%information about a other user
% returns the canonical information about that user

-spec info_about(
    Userid :: non_neg_integer(),
    Otherid :: non_neg_integer() ) -> list().

info_about( _Userid, Otherid ) ->
    canonical(Otherid).

%information about a other user
% determine what's the relation between the user and the other
% the relation could then be :
% contact, 
% self, which means the user is looking at his own info
% none, which means users are not connected
%
-spec info_about(
    Userid :: non_neg_integer(),
    Otherid :: non_neg_integer(),
    Section :: list() | binary(),
    Field :: list() | binary()) -> list().

info_about(Userid, Userid, Section, <<"addresses">>) ->
    infotree_get_addresses_for(Userid, "self", Section);

    

info_about(Userid, Otherid, Section, <<"addresses">>) ->
    case connected_contacts(Userid, Otherid) of
        [] ->
            infotree_get_addresses_for(Otherid, "all", Section);

        [_Timestamp] ->
            infotree_get_addresses_for(Otherid, "contact", Section)
    end;

info_about(_Userid, _Otherid, _Section, _Field) ->
    []. %infotree_get_for(Userid, "self", Section, Field);

-spec info_about(
    Userid :: non_neg_integer(),
    Otherid :: non_neg_integer(),
    Section :: list() | binary()) -> list().

info_about(_Userid, Otherid, <<"About">>) ->
    Ops = [
        hyd:operation(<<"about">>, infotree(), [ Otherid ])
    ],
    run(Ops);

info_about(Userid, Userid, Section) ->
    infotree_get_for(Userid, "self", Section);

info_about(Userid, Otherid, Section) ->
    case connected_contacts(Userid, Otherid) of
        [] ->
            infotree_get_for(Otherid, "all", Section);

        [_Timestamp] ->
            infotree_get_for(Otherid, "contact", Section)
    end.

infotree_get_for(Userid, Relation, Section) ->
    Ops = [
        hyd:operation(<<"getFor">>, infotree(), [ Userid, Relation, Section ])
    ],
    run(Ops).

infotree_get_address_for(Userid, Relation, Section, Index) ->
    Ops = [
        hyd:operation(<<"getAddressFor">>, infotree(), [ Userid, Relation, Section, Index ])
    ],
    run(Ops).

infotree_set_visibility(Userid, Key, Field, Index, Visibility) ->
    Filtered = quote(Visibility),
    Ops = [
        hyd:operation(<<"setVisibility">>, infotree(), [ Userid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

infotree_set_visibility_tmp(Userid, Key, Field, Index, Visibility, Tmp) ->
    Filtered = quote(Visibility),
    Ops = [
        hyd:operation(<<"setVisibility">>, infotree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

-spec connected_contacts(
    Userid :: non_neg_integer(),
    Contactid :: non_neg_integer() ) -> list().

connected_contacts(Userid, Contactid) ->
    Ops = [
    	hyd:operation(<<"connectedContacts">>, module(), [ Userid, Contactid ])
    ],
    run(Ops).


% Retrieving own information for a contact (OtherId)
-spec info_own_contact(
    Userid :: non_neg_integer(),
    Otherid :: non_neg_integer(),
    Section :: list() | binary() ) -> list().

info_own_contact(Userid, Contactid, Section) ->
    infotree_get_own_value(Userid, Contactid, Section).

info_own_contact(Userid, Contactid, Section, <<"addresses">>) ->
    infotree_get_own_addresses(Userid, Contactid, Section);
    
info_own_contact(_Userid, _Contactid, _Section, _) ->
    [].

info_own_contact(Userid, Contactid, Section, <<"address">>, Index) ->
    infotree_get_own_address(Userid, Contactid, Section, Index);

info_own_contact(_Userid, _Contactid, _Section, _, _) ->
    [].

-spec contacts_tree( 
    Userid :: non_neg_integer()) -> list().

contacts_tree(Userid) ->
    % Get all categories
    case contacts_categories(Userid) of
        [] ->
            [];

        Categories ->
            contacts_tree(Userid, Categories, [])
    end.

contacts_tree(_UserId,[],Result) ->
    Result;
contacts_tree(Userid, Categories, Result) ->
    lists:foldl( fun(Category, Acc) ->
        case contacts_info_from_category(Userid, Category) of
            [] ->
                Acc;
            Infos ->
                %?DEBUG("Infos: ~p", [ Infos ]),
                Infos ++ Acc
        end
    end, Result, Categories).

% Returns only one of these:
% - non empty binary
% - []
config_get_value(UserId, Key) ->
    Ops = [
        hyd:operation(<<"configGet">>, module(), [ UserId, Key ])
    ],
    case run(Ops) of
       [<<>>] ->
           [];
       [Result] ->
           Result;
       _A ->
           _A
    end.

config_set_value(UserId, Key, Value) ->
    FilteredValue = quote(Value),
    Ops = [
        hyd:operation(<<"configSet">>, module(), [ UserId, Key, FilteredValue ])
    ],
    run(Ops).

config_all(UserId) ->
    Ops = [
        hyd:operation(<<"configAll">>, module(), [ UserId ])
    ],
    case run(Ops) of
       [<<>>] ->
           [];
       KVs when is_list(KVs) ->
           lists:map(fun({K,V}) ->
               {K, V}
           end, KVs);

       _A ->
           _A
    end.


%% Sessions

session_init(Ip, Port) ->
    Ops = [
        hyd:operation(<<"sessionInit">>, module(), [ Ip, Port ])
    ],
    run(Ops).
    
session_new(Sessionid, Userid, Ip, Port) ->
    Ops = [
        hyd:operation(<<"sessionNew">>, module(), [ Sessionid, Userid, Ip, Port ])
    ],
    run(Ops).

session_end(Sessionid, Seqid) ->
    Ops = [
%        hyd:operation(<<"sessionEnd">>, module(), [ Sessionid, Seqid ])
        hyd:operation(<<"end">>, session(), [ Sessionid, Seqid ])
    ],
    run(Ops).

session_dns(Ip, Reverse) ->
    Ops = [
        hyd:operation(<<"sessionDns">>, module(), [ Ip, Reverse ])
    ],
    run(Ops).
    
read(UserId, Subscripts) ->
    io:format("Accessing: ~p(~p)\n", [ UserId, Subscripts ]),
    Args = gtmproxy_fmt:ref(Subscripts),
    Op = hyd:operation(<<"read">>, module(), [ UserId, Args ]),
    run([ Op ]).

write(UserId, Subscripts, Value) ->
    io:format("Writing: ~p(~p)\n", [ UserId, Subscripts ]),
    Args = gtmproxy_fmt:ref(Subscripts),
    Op = hyd:operation(<<"write">>, module(), [ UserId, Args, Value ]),
    hyd:call([ Op ]).

delete(Userid, Subscripts) ->
    io:format("Killing: ~p(~p)\n", [ Userid, Subscripts ]),
    Args = gtmproxy_fmt:ref(Subscripts),
    Op = hyd:operation(<<"kill">>, module(), [ Userid, Args ]),
    hyd:call([ Op ]).


% REGISTRY(EE)
registry_add_value(Userid, Key, Subkey, Value) ->
    Ops = [
        hyd:operation(<<"registryAdd">>, module(), [ Userid, Key, Subkey, Value ])
    ],
    run(Ops).

registry_set_value(Userid, Key, Values) when is_list(Values) ->
    lists:foldl( fun
        ({K,V}, _Acc) ->
            Ops = [
            hyd:operation(<<"registryAdd">>, module(), [ Userid, Key, K, V ])
            ],
            run(Ops);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
            Ops = [
                hyd:operation(<<"registryAdd">>, module(), [ Userid, Key, K, V ])
            ],
            run(Ops)
            end, KVs);

        (Value, _Acc) ->
            %% HACK HACK Shortcuts for setting multiple **'config'** not registry !
            registry_add_value(Userid, Key, Value, [])

    end, [], Values);

registry_set_value(Userid, Key, Value) ->
    registry_add_value(Userid, Key, Value, []).

registry_get_value(Userid, Key) ->
    Ops = [
        hyd:operation(<<"registryGet">>, module(), [ Userid, Key ])
    ],
    run(Ops).

registry_get_value(Userid, Key, Subkey) ->
    Ops = [
        hyd:operation(<<"registryGet">>, module(), [ Userid, Key, Subkey ])
    ],
    run(Ops).

registry_get_old_value(Userid, Key, Subkey) ->
    registry_get_old_value(Userid, Key, Subkey, []).

registry_get_old_value(Userid, Key, Subkey, Old) ->
    Ops = [
        hyd:operation(<<"registryGetOld">>, module(), [ Userid, Key, Subkey, Old ])
    ],
    run(Ops).

% Infotree
infotree_new_multiple(Userid, Key, Type) ->
    Ops = [
        hyd:operation(<<"newMultiple">>, infotree(), [ Userid, Key, Type ])
    ],
    run(Ops).

infotree_new_own_multiple(Userid, Contactid, Key, Type) ->
    Ops = [
        hyd:operation(<<"newOwnMultiple">>, infotree(), [ Userid, Contactid, Key, Type ])
    ],
    run(Ops).
    
infotree_add_value(Userid, Key, Subkey, Value) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"add">>, infotree(), [ Userid, Key, Subkey, Filtered ])
    ],
    run(Ops).

infotree_add_own_value(Userid, Contactid, Key, Subkey, Value) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"addOwn">>, infotree(), [ Userid, Contactid, Key, Subkey, Filtered ])
    ],
    run(Ops).


infotree_set_value(Userid, Key, Values) when is_list(Values) ->
    lists:foldl( fun
        (_, {error, _} = Error) ->
            Error;
            
        ({K,V}, Acc) ->
            %[ Index ] = infotree_add_value(Userid, Key, K, V),
            case infotree_add_value(Userid, Key, K, V) of
                [ Index ] ->
                    [ {K, Index} | Acc ];
                {error, _} = Error ->
                    Error
                    %[ Error | Acc ]
            end;

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                infotree_add_value(Userid, Key, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values).

infotree_set_value(Userid, Key, Values, Field) when is_list(Values) ;
    Field =:= <<"address">> ->
    case infotree_new_multiple(Userid, Key, Field) of
        {error, _} = Err ->
            Err;

        [Index] ->
            infotree_set_value(Userid, Key, Values, Field, Index),
            Index
    end.

infotree_set_own_value(Userid, Contactid, Key, Values) when is_list(Values) ->
    lists:foldl( fun
        ({K,V}, _Acc) ->
            infotree_add_own_value(Userid, Contactid, Key, K, V);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                infotree_add_own_value(Userid, Contactid, Key, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values).

infotree_set_own_value(Userid, Contactid, Key, Values, Field) when is_list(Values) ;
    Field =:= <<"address">> ->
    case infotree_new_own_multiple(Userid, Contactid, Key, Field) of
        {error, _} = Err ->
            Err;

        [Index] ->
            infotree_set_own_value(Userid, Contactid, Key, Values, Field, Index),
            Index
    end.



infotree_set_value(Userid, Key, Values, <<"address">>, Index) when is_list(Values) ->
    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            infotree_set_address_title(Userid, Key, Index, V);

        ({K,V}, _Acc) ->
            infotree_set_address_value(Userid, Key, Index, K, V);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                infotree_set_address_value(Userid, Key, Index, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

infotree_set_value(Userid, Key, Value, Field, Index) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"set">>, infotree(), [ Userid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

infotree_set_own_value(Userid, Contactid, Key, Values, <<"address">>, Index) when is_list(Values) ->
    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            infotree_set_own_address_title(Userid, Contactid, Key, Index, V);

        ({K,V}, _Acc) ->
            infotree_set_own_address_value(Userid, Contactid, Key, Index, K, V);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
            infotree_set_own_address_value(Userid, Contactid, Key, Index, K, V)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

infotree_set_own_value(Userid, Contactid, Key, Value, Field, Index) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"setOwn">>, infotree(), [ Userid, Contactid, Key, Field, Index, Filtered ])
    ],
    run(Ops).


infotree_set_label(Userid, Key, Field, Index, Label) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setLabel">>, infotree(), [ Userid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

infotree_set_own_label(Userid, Contactid, Key, Field, Index, Label) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setOwnLabel">>, infotree(), [ Userid, Contactid, Key, Field, Index, Filtered ])
    ],
    run(Ops).

% infotree_set_value(Userid, Key, Value) ->
%     infotree_add_value(Userid, Key, Value, []).

infotree_get_value(Userid, Key) ->
    Ops = [
        hyd:operation(<<"get">>, infotree(), [ Userid, Key ])
    ],
    run(Ops).

    % case run(Ops) of
    %     [<<>>] ->
    %         [];
    %     KVs when is_list(KVs) ->
    %         lists:map(fun({K,V}) ->
    %                 {K, unquote(V)}
    %                 end, KVs);

    %     _A ->
    %         _A
    % end.

infotree_get_own_value(Userid, Contactid, Key) ->
    Ops = [
        hyd:operation(<<"getOwn">>, infotree(), [ Userid, Contactid, Key ])
    ],
    run(Ops).

    %case run(Ops) of
    %    [<<>>] ->
    %        [];

    %    KVs when is_list(KVs) ->
    %        lists:map(fun({K,V}) ->
    %                {K, unquote(V)}
    %                end, KVs);
    %    _A ->
    %        _A
    %end.

infotree_get_value(Userid, Key, Subkey) ->
    Ops = [
        hyd:operation(<<"get">>, infotree(), [ Userid, Key, Subkey ])
    ],
    run(Ops).

    %case run(Ops) of
    %    [<<>>] ->
    %        [];
    %    [Result] ->
    %        unquote(Result);
    %    _A ->
    %        _A
    %end.

infotree_get_own_value(Userid, Contactid, Key, Subkey) ->
    Ops = [
        hyd:operation(<<"getOwn">>, infotree(), [ Userid, Contactid, Key, Subkey ])
    ],
    run(Ops).

    %case run(Ops) of
    %    [<<>>] ->
    %        [];
    %    [Result] ->
    %        unquote(Result);
    %    _A ->
    %        _A
    %end.

infotree_get_field(Category, Field) ->
    Ops = [
        hyd:operation(<<"getField">>, infotree(), [ Category, Field ])
    ],
    run(Ops).

% infotree_get_addresses(Userid,Category) ->
%     Ops = [
%         hyd:operation(<<"getAddresses">>, infotree(), [ Userid, Category ])
%     ],
%     case run(Ops) of
%         [] ->
%             [];
% 
%         Indexes ->
%             lists:foldl( fun(Index, Acc) ->
%                 [ Addr ] = infotree_get_address(Userid,Category,Index),
%                 [ Addr | Acc ]
%             end, [], Indexes)
%     end.

infotree_get_addresses(Userid,Category) ->
    Ops = [
        hyd:operation(<<"getAddresses">>, infotree(), [ Userid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index, Acc) ->
                case infotree_get_address(Userid,Category,Index) of
                    [] ->
                        Acc;
                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

infotree_get_addresses_for(Userid, Relation, Category) ->
    Ops = [
        hyd:operation(<<"getAddresses">>, infotree(), [ Userid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index, Acc) ->
                case infotree_get_address_for(Userid, Relation, Category, Index) of
                    [] ->
                        Acc;

                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

infotree_get_own_addresses(Userid,Contactid,Category) ->
    Ops = [
        hyd:operation(<<"getOwnAddresses">>, infotree(), [ Userid, Contactid, Category ])
    ],
    case run(Ops) of
        [] ->
            [];

        Indexes ->
            lists:foldl( fun(Index,Acc) ->
                case infotree_get_own_address(Userid,Contactid,Category,Index) of
                    [] ->
                        Acc;
                    [ Addr ] ->
                        [ Addr | Acc ]
                end
            end, [], Indexes)
    end.

infotree_get_address(Userid,Category,Index) ->
    Ops = [
        hyd:operation(<<"getAddress">>, infotree(), [ Userid, Category, Index ])
    ],
    run(Ops).

infotree_get_own_address(Userid,Contactid,Category,Index) ->
    Ops = [
        hyd:operation(<<"getOwnAddress">>, infotree(), [ Userid, Contactid, Category, Index ])
    ],
    run(Ops).

infotree_set_address_value(Userid, Category, Index, Key, Value) ->
    Ops = [
        hyd:operation(<<"setAddressValue">>, infotree(), [ Userid, Category, Index, Key, quote(Value) ])
    ],
    run(Ops).

infotree_set_own_address_value(Userid,Contactid,Category,Index,Key,Value) ->
    Ops = [
        hyd:operation(<<"setOwnAddressValue">>, infotree(), [ Userid, Contactid, Category, Index, Key, quote(Value) ])
    ],
    run(Ops).

infotree_set_address_title(Userid,Category,Index,Title) ->
    Ops = [
        hyd:operation(<<"setAddressTitle">>, infotree(), [ Userid, Category, Index, quote(Title) ])
    ],
    run(Ops).

infotree_set_own_address_title(Userid,Contactid,Category,Index,Title) ->
    Ops = [
        hyd:operation(<<"setOwnAddressTitle">>, infotree(), [ Userid, Contactid, Category, Index, quote(Title) ])
    ],
    run(Ops).

% Using temporary storage, validate it or cancel it
infotree_set_value_tmp(Userid, Key, Values, Field, Index, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->
    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            infotree_set_address_title_tmp(Userid, Key, Index, V, Tmp);

        ({K,V}, _Acc) ->
            infotree_set_address_value_tmp(Userid, Key, Index, K, V, Tmp);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                infotree_set_address_value_tmp(Userid, Key, Index, K, V, Tmp)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

infotree_set_value_tmp(Userid, Key, Value, Field, Index, Tmp) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"set">>, infotree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

infotree_set_address_value_tmp(Userid, Category, Index, Key, Value, Tmp) ->
    Ops = [
        hyd:operation(<<"setAddressValue">>, infotree(), [ Userid, Category, Index, Key, quote(Value), Tmp ])
    ],
    run(Ops).

infotree_set_address_title_tmp(Userid, Category, Index, Title, Tmp) ->
    Ops = [
        hyd:operation(<<"setAddressTitle">>, infotree(), [ Userid, Category, Index, quote(Title), Tmp ])
    ],
    run(Ops).

infotree_set_own_value_tmp(Userid, Contactid, Key, Values, Field, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->
    case infotree_new_own_multiple(Userid, Contactid, Key, Field) of
        {error, _} = Err ->
            Err;

        [Index] ->
            infotree_set_own_value_tmp(Userid, Contactid, Key, Values, Field, Index, Tmp),
            Index
    end.

infotree_set_own_value_tmp(Userid, Contactid, Key, Values, Field, Index, Tmp) when is_list(Values) ;
    Field =:= <<"address">> ->

    lists:foldl( fun
        ({<<"title">>, V}, _Acc) ->
            infotree_set_own_address_title_tmp(Userid, Contactid, Key, Index, V, Tmp);

        ({K,V}, _Acc) ->
            infotree_set_own_address_value_tmp(Userid, Contactid, Key, Index, K, V, Tmp);

        ([{_K, _V}|_] = KVs, _Acc) ->
            lists:foreach( fun({K,V}) ->
                infotree_set_own_address_value_tmp(Userid, Contactid, Key, Index, K, V, Tmp)
            end, KVs);

        (_, Acc) ->
            Acc

    end, [], Values);

infotree_set_own_value_tmp(Userid, Contactid, Key, Value, Field, Index, Tmp) ->
    Filtered = quote(Value),
    Ops = [
        hyd:operation(<<"setOwn">>, infotree(), [ Userid, Contactid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

infotree_set_label_tmp(Userid, Key, Field, Index, Label, Tmp) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setLabel">>, infotree(), [ Userid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

infotree_set_own_label_tmp(Userid, Contactid, Key, Field, Index, Label, Tmp) ->
    Filtered = quote(Label),
    Ops = [
        hyd:operation(<<"setOwnLabel">>, infotree(), [ Userid, Contactid, Key, Field, Index, Filtered, Tmp ])
    ],
    run(Ops).

infotree_set_own_address_value_tmp(Userid, Contactid, Category, Index, Key, Value, Tmp) ->
    Ops = [
        hyd:operation(<<"setOwnAddressValue">>, infotree(), [ Userid, Contactid, Category, Index, Key, quote(Value), Tmp ])
    ],
    run(Ops).

infotree_set_own_address_title_tmp(Userid, Contactid, Category, Index, Title, Tmp) ->
    Ops = [
        hyd:operation(<<"setOwnAddressTitle">>, infotree(), [ Userid, Contactid, Category, Index, quote(Title), Tmp ])
    ],
    run(Ops).

infotree_cancel(Userid, Tmp) ->
    Ops = [
        hyd:operation(<<"cancel">>, infotree(), [ Userid, Tmp ])
    ],
    run(Ops).

infotree_validate(Userid, Tmp) ->
    Ops = [
        hyd:operation(<<"validate">>, infotree(), [ Userid, Tmp ])
    ],
    run(Ops).

infotree_contract(Userid, Tmp, Category, Field, Index) ->
    Ops = [
        hyd:operation(<<"contract">>, infotree(), [ Userid, Tmp, Category, Field, Index ])
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

async_run(TransId, Method, Module, Args ) ->
    db:cast(TransId, Method, Module, Args),
    receive
        {ok, Elements } ->

            case lists:foldl( fun
                (_, {error, _} = _Acc) ->
                    _Acc;
                ({error, _} = _Error, _) ->
                    _Error;
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];
                        {error, _} = Error ->
                            Error
                    end
                end, [], Elements) of

                    {error, _} = Error ->
                        Error;

                    Results when is_list(Results) ->
                        lists:flatten(Results)
                end;
        _ ->
            internal_error(833, [Method, Module])
    after 5000 ->
        {error, timeout}
    end.
