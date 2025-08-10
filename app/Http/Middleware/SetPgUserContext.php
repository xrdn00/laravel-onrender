<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class SetPgUserContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $userId = Auth::id();
        $role = Auth::user()?->role ?? 'user';

        // Set a per-connection GUC that our RLS policies read via app.current_user_id()
        // Use set_config so it is scoped to this connection; reset to empty when unauthenticated.
        $value = $userId ? (string) $userId : '';
        DB::statement("select set_config('app.user_id', ?, false)", [$value]);
        DB::statement("select set_config('app.user_role', ?, false)", [$userId ? (string) $role : '']);

        return $next($request);
    }
}


