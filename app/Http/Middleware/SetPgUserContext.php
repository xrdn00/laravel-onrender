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

        // Set session-scoped GUCs for the duration of this request, then clear them.
        // Using session scope (is_local = false) ensures they persist across multiple
        // DB statements within the same request even without an explicit transaction.
        DB::statement("select set_config('app.user_id', ?, false)", [$userId ? (string) $userId : '']);
        DB::statement("select set_config('app.user_role', ?, false)", [$userId ? (string) $role : '']);

        try {
            return $next($request);
        } finally {
            // Clear to avoid leaking context between requests in pooled connections
            DB::statement("select set_config('app.user_id', '', false)");
            DB::statement("select set_config('app.user_role', '', false)");
        }
    }
}


