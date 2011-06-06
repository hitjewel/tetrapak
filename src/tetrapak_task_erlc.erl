%    __                        __      _
%   / /__________ __   _____  / /___  (_)___  ____ _
%  / __/ ___/ __ `/ | / / _ \/ / __ \/ / __ \/ __ `/
% / /_/ /  / /_/ /| |/ /  __/ / /_/ / / / / / /_/ /
% \__/_/   \__,_/ |___/\___/_/ .___/_/_/ /_/\__, /
%                           /_/            /____/
%
% Copyright (c) Travelping GmbH <info@travelping.com>

-module(tetrapak_task_erlc).
-behaviour(tetrapak_task).
-export([check/1, run/2]).

-task({"build:erlang", "Build Erlang modules"}).
-task({"clean:erlang", "Delete compiled Erlang modules"}).

-record(erl, {
    file,
    module,
    behaviours = [],
    attributes = [],
    includes = [],
    mtime,
    invalid = false
}).

%% ------------------------------------------------------------
%% -- Task API
check("build:erlang") ->
    EbinDir             = tetrapak:subdir("ebin"),
    SrcDir              = tetrapak:subdir("src"),
    ExtraCompileOptions = tetrapak:get("config:ini:build:erlc_options", []),
    CompileOptions      = [{outdir, EbinDir}, {i, tetrapak:subdir("include")}, return_errors, return_warnings, debug_info]
                          ++ ExtraCompileOptions,
    Sources             = lists:sort(fun compile_order/2, erlang_source_files(SrcDir)),
    FileList            =
        lists:flatmap(fun (File) ->
                          case needs_compile(CompileOptions, EbinDir, File) of
                              true  -> [{File, CompileOptions}];
                              false -> []
                          end
                      end, Sources),
    case FileList of
        [] -> done;
        _  -> {needs_run, FileList}
    end.

run("build:erlang", ErlFiles) ->
    BaseDir = tetrapak:dir(),
    EbinDir = tetrapak:subdir("ebin"),
    Fail = lists:foldr(fun ({File, CompileOptions}, DoFail) ->
                               try_load(EbinDir, File#erl.behaviours),
                               case compile:file(File#erl.file, CompileOptions) of
                                   {ok, _Module} ->
                                       DoFail;
                                   {ok, _Module, Warnings} ->
                                       show_errors(BaseDir, "Warning: ", Warnings),
                                       DoFail;
                                   {error, Errors, Warnings} ->
                                       show_errors(BaseDir, "Error: ", Errors),
                                       show_errors(BaseDir, "Warning: ", Warnings),
                                       true
                               end
                       end, false, ErlFiles),
    if Fail -> tetrapak:fail();
       true -> ok
    end;

run("clean:erlang", _) ->
    tpk_file:delete("\\.beam$", tetrapak:subdir("ebin")).

%% ------------------------------------------------------------
%% -- Helpers
show_errors(BaseDir, Prefix, Errors) ->
    lists:foreach(fun ({FileName, FileErrors}) ->
                          case lists:prefix(BaseDir, FileName) of
                              true ->
                                  Path = tpk_file:rebase_filename(FileName, BaseDir, "");
                              false ->
                                  Path = FileName
                          end,
                          lists:foreach(fun ({Line, Module, Error}) ->
                                                io:format("~s:~b: ~s~s~n", [Path, Line, Prefix, Module:format_error(Error)])
                                        end, FileErrors)
                  end, Errors).

compile_order(File1, File2) ->
    lists:member(File1#erl.module, File2#erl.behaviours).

try_load(EbinDir, ModList) ->
    lists:foreach(fun (Mod) ->
                          MAtom = list_to_atom(Mod),
                          case code:is_loaded(MAtom) of
                              false -> code:load_abs(filename:join(EbinDir, Mod ++ ".beam"));
                              _     -> ok
                          end
                  end, ModList).

needs_compile(NewCOptions, Ebin, #erl{module = Mod, attributes = Attrs, includes = Inc, mtime = ModMTime}) ->
    Beam = filename:join(Ebin, tpk_util:f("~s.beam", [Mod])),
    COptions = proplists:get_value(compile, Attrs, []) ++ NewCOptions,
    case filelib:is_regular(Beam) of
        false -> true;
        true  ->
            {ok, {_, [{compile_info, ComInfo}]}} = beam_lib:chunks(Beam, [compile_info]),
            BeamCOptions = proplists:get_value(options, ComInfo),
            BeamMTime    = tpk_file:mtime(Beam),
            ((BeamMTime =< ModMTime)) %% beam is older
            orelse lists:usort(BeamCOptions) /= lists:usort(COptions) %% compiler options changed
            orelse lists:any(fun (I) -> tpk_file:mtime(I) >= BeamMTime end, Inc) %% include file changed
    end.

erlang_source_files(Path) ->
    case filelib:is_dir(Path) of
        true ->
            tpk_file:walk(fun (File, Acc) ->
                                  case tpk_util:match("\\.erl$", File) of
                                      true  -> [scan_source(File) | Acc];
                                      false -> Acc
                                  end
                          end, [], Path);
        false ->
            tetrapak:fail("not a directory: ~s", [Path])
    end.

scan_source(Path) ->
    case epp_dodger:quick_parse_file(Path, []) of
        {ok, Forms} ->
            Rec = #erl{mtime = tpk_file:mtime(Path), file = Path, module = filename:basename(Path, ".erl")},
            lists:foldl(fun (F, Acc) -> do_form(Path, F, Acc) end, Rec, tl(Forms))
    end.

do_form(File, {attribute, _, file, {IncludeFile, _}}, R) when File /= IncludeFile ->
    R#erl{includes = [IncludeFile | R#erl.includes]};
do_form(_File, {attribute, _, module, Module}, R) when is_atom(Module) ->
    R#erl{module = atom_to_list(Module)};
do_form(_File, {attribute, _, module, Module}, R) when is_list(Module) ->
    R#erl{module = string:join([atom_to_list(A) || A <- Module], ".")};
do_form(_File, {attribute, _, module, {Module, _}}, R) when is_atom(Module) ->
    R#erl{module = atom_to_list(Module)};
do_form(_File, {attribute, _, module, {Module, _}}, R) when is_list(Module) ->
    R#erl{module = string:join([atom_to_list(A) || A <- Module], ".")};
do_form(_File, {attribute, _, behaviour, Behaviour}, R) ->
    R#erl{behaviours = [atom_to_list(Behaviour) | R#erl.behaviours]};
do_form(_File, {attribute, _, behavior, Behaviour}, R) ->
    R#erl{behaviours = [atom_to_list(Behaviour) | R#erl.behaviours]};
do_form(_File, {attribute, _, Attr, Value}, R) ->
    case proplists:get_value(Attr, R#erl.attributes) of
        undefined -> R#erl{attributes = [{Attr, avalue(Value)} | R#erl.attributes]};
        Existing  -> R#erl{attributes = lists:keyreplace(Attr, 1, R#erl.attributes, {Attr, avalue(Value) ++ Existing})}
    end;
do_form(_File, {error, _}, R) ->
    R#erl{invalid = true};
do_form(_File, _, R) ->
    R.

avalue(Val) when is_list(Val) -> Val;
avalue(Val)                   -> [Val].