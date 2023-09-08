/*
 * Module: argus_error
 * Purpose: Structured error types and diagnostic reporting.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_error, [
    raise_argus_error/3,
    catch_argus_error/3,
    format_argus_error/2,
    argus_assert/2
]).

/**
 * raise_argus_error(+Category, +Message, +Context)
 * Throws a formal structured exception term: error(argus_error(Category, Message, Context), _).
 */
raise_argus_error(Category, Message, Context) :-
    throw(error(argus_error(Category, Message, Context), _)).

/**
 * catch_argus_error(:Goal, :Handler, -Result)
 */
catch_argus_error(Goal, Handler, Result) :-
    catch(Goal, error(argus_error(Cat, Msg, Ctx), _), call(Handler, Cat, Msg, Ctx, Result)).

/**
 * format_argus_error(+ErrorTerm, -FormattedAtom)
 */
format_argus_error(error(argus_error(Category, Message, Context), _), Formatted) :-
    format(atom(Formatted), "[ARGUS ~w] ~w (Context: ~w)", [Category, Message, Context]).

/**
 * argus_assert(+Condition, +ErrorMessage)
 */
argus_assert(Condition, _ErrorMessage) :-
    Condition, !.
argus_assert(_Condition, ErrorMessage) :-
    raise_argus_error(assertion_failed, ErrorMessage, []).
