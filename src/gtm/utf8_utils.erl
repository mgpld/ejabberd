-module(utf8_utils).
% Created utf8_utils.erl the 20:31:29 (11/07/2016) on core
% Last Modification of utf8_utils.erl at 11:32:40 (31/07/2016) on core
% 
% Author: "ak" <ak@harmonygroup.net>

-export([
    count/1, count/2
]).

count(Bin) ->
    count(Bin, 0).

count(<<>>, Count) ->
    Count;
count(<<_/utf8,_/utf8,_/utf8,Rest/binary>>, Count) ->
    count(Rest, Count + 3);
count(<<_/utf8,_/utf8,Rest/binary>>, Count) ->
    count(Rest, Count + 2);
count(<<_/utf8,Rest/binary>>, Count) ->
    count(Rest, Count + 1);
count(<<_,Rest/binary>>, Count) ->
    count(Rest, Count + 1).
