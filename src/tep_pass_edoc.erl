%    __                        __      _
%   / /__________ __   _____  / /___  (_)___  ____ _
%  / __/ ___/ __ `/ | / / _ \/ / __ \/ / __ \/ __ `/
% / /_/ /  / /_/ /| |/ /  __/ / /_/ / / / / / /_/ /
% \__/_/   \__,_/ |___/\___/_/ .___/_/_/ /_/\__, /
%                           /_/            /____/
%
% Copyright (c) Travelping GmbH <info@travelping.com>

-module(tep_pass_edoc).
-behaviour(tep_pass).
-export([check/1, run/2]).

-pass({"doc:edoc", "Generate edoc documentation"}).
-pass({"clean:edoc", "Delete generated documentation"}).

-define(DOC_DIR, tetrapak:subdir(tetrapak:get("config:ini:doc:directory", "doc"))).

check("clean:edoc") ->
    filelib:is_dir(?DOC_DIR).

run("doc:edoc", _) ->
    DD = ?DOC_DIR,
    tep_file:mkdir(DD),
    edoc:application(tetrapak:get("config:appfile:name"), [{dir, DD}]);

run("clean:edoc", _) ->
	DD = ?DOC_DIR,
    tep_file:delete("(\\.(html|css|png)$)|edoc-info", DD),
	file:del_dir(DD),
	ok.
