<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class SetPgLoginEmail
{
    public function handle(Request $request, Closure $next): Response
    {
        $email = (string) $request->input('email', '');
        DB::statement("select set_config('app.login_email', ?, false)", [$email]);

        try {
            return $next($request);
        } finally {
            DB::statement("select set_config('app.login_email', '', false)");
        }
    }
}


