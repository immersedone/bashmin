####
#    File: default.vcl
#    Author: Truc Minh Phan <immersedone>
#    Last Modified: Truc Minh Phan (04/12/2019)
#    Description:
#
#    This file contains the default/base VCL configurations for Varnish
#    HTTP Cache Server. It includes standardized backends for 2 versions
#    of PHP (latest/keep-alive) and one NodeJS example.
#
#    It also removes certain headers from the response for security purposes.
#
#    Varnish Docs: https://varnish-cache.org/docs/
#    Varnish Examples: https://varnish-cache.org/trac/wiki/VCLExamples
#
##

# Define the VCL Version
vcl 4.0;


# Import Libraries
import std;


# Backend Configurations

### === FORWARD TO APACHE === ###

#### --- PHP7.4 - Default Version --- ####
backend default {

    # Base Varnish Director Configurations
    .host = "127.0.0.1";
    .port = "8080";

    # Backend Health-Check
    .probe = {
        .url = "/";
        .interval = 5s;
        .timeout = 1s;
        .window = 5;
        .threshold = 3;
    }

}



#### --- PHP7.3 - Secondary Versions --- ####
backend php73 {

    # Base Varnish Director Configurations
    .host = "127.0.0.1";
    .port = "8081";

    # Backend Health-Check
    .probe = {
        .url = "/";
        .interval = 5s;
        .timeout = 5s;
        .window = 5;
        .threshold = 3;
    }

}

### === END FORWARD TO APACHE === ###



### === FORWARD TO NODEJS SERVERS/PROJECTS === ###

#### --- NodeJS Projects Ports: 3000+ --- ####
backend www-node {

    # Base Varnish Director Configurations
    .host = "127.0.0.1";
    .port = "3027";

    # Backend Health-Check
    .probe = {
        .url = "/";
        .interval = 5s;
        .timeout = 5s;
        .window = 5;
        .threshold = 3;
    }

}

### === END FORWARD TO NODEJS SERVER/PROJECTS === ###



# Receive Hook: Inbound Requests sent over from Nginx
sub vcl_recv {

    #####
    #    Description: This stub (vcl_revc) is used to direct inbound
    #    traffic from certain ports and redirects them to the
    #    appropriate backend; either NodeJS or Apache2/PHP stack.
    #
    #    Lifecycle: Before Varnish Cache Hit
    ##

    ### === COOKIE MANIPULATION === ###
    if( req.http.Cookie ) {
        # Debuggin to Log
        #std.log( "RECV: " + req.http.host + req.url );
        #std.log( "Cookie Before: " + req.http.Cookie );

        # Remove has_js and Cloudflare/Google Analytics __* cookies.
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");
        # Remove a ";" prefix, if present.
        set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

        if( req.http.Cookie == "" ) {
            unset req.http.Cookie;
        }

        # Debugging to Log
        #std.log( "Cookie After: " + req.http.Cookie );

    } else {
        std.log( "No Cookies!" );
    }

    ### === END COOKIE MANIPULATION === ###


    #### === START BACKEND FORWARDING === ####

    ### Default: Apache2/PHP7.4-FPM Backend
    if( std.port( local.ip ) == 8090 ) {
        set req.backend_hint = default;
    }

    ### Apache2/PHP7.3-FPM Backend
    if( std.port( local.ip ) == 8091 ) {
        set req.backend_hint = php73;
    }

    ### NodeJS Application
    if( std.port( local.ip ) == 8095 ) {
        set req.backend_hint = www-node;
    }

    #### === END BACKEND FORWARDING === ####


}

# Post Hook: After Backend Returns Response
sub vcl_backend_response {

    # Modify how long the Backend Reponse Should Live
    set beresp.ttl = 1m;
    set beresp.grace = 1h;


# Ban lurker friendly header
  set beresp.http.url = bereq.url;

  # Add a grace in case the backend is down
  set beresp.grace = 1h;

  if (bereq.http.Cookie ~ "(UserID|_session)") {
      #set beresp.http.X-Cacheable = "NO:Got Session";
      set beresp.uncacheable = true;
  } elsif (beresp.ttl <= 0s) {
      # Varnish determined the object was not cacheable
      #set beresp.http.X-Cacheable = "NO:Not Cacheable";
      #set beresp.http.X-Cache-TTL = beresp.ttl;
  } elsif (beresp.http.set-cookie) {
      # You don't wish to cache content for logged in users
      #set beresp.http.X-Cacheable = "NO:Set-Cookie";
      set beresp.uncacheable = true;
  } elsif (beresp.http.Cache-Control ~ "private") {
      # You are respecting the Cache-Control=private header from the backend
      #set beresp.http.X-Cacheable = "NO:Cache-Control=private";
      set beresp.uncacheable = true;
  } else {
      # Varnish determined the object was cacheable
      #set beresp.http.X-Cacheable = "YES";
  }


    # This block will make sure that if the upstream returns a 5xx, but we have the response in the cache (even if it's expired),
    # we fall back to the cached value (until the grace period is over).
    if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504)
    {
        # This check is important. If is_bgfetch is true, it means that we've found and returned the cached object to the client,
        # and triggered an asynchoronus background update. In that case, if it was a 5xx, we have to abandon, otherwise the previously cached object
        # would be erased from the cache (even if we set uncacheable to true).
        if (bereq.is_bgfetch)
        {
            return (abandon);
        }

        # We should never cache a 5xx response.
        set beresp.uncacheable = true;
    }

    # Modify how long the Backend Reponse Should Live
    set beresp.ttl = 1m;
    set beresp.grace = 1h;

}


# Delivery: Run after backend is received and mutated
sub vcl_deliver {

    #### ---  Remove Headers for Security --- ####
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    unset resp.http.Age;
    unset resp.http.ETag;
    unset resp.http.X-Powered-By;

    if (obj.hits > 0) { # Add debug header to see if it's a HIT/MISS and the number of hits, disable when not needed
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    # Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
    # and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
    # So take hits with a grain of salt
    #set resp.http.X-Cache-Hits = obj.hits;

    #### --- Return the Response Delivery --- ###
    return( deliver );

}



# Cache-HIT: Once page/item has been found within the Cache Store
sub vcl_hit {

    # Check Object is within the Time-To-Live
    if( obj.ttl >= 0s) {
        # No issues with the current request, continue.
        return( deliver );
    }

    # Check if Object is within Grace Period
    if( obj.ttl + obj.grace > 0s ) {
        # Still within Grace Period; serve the cached content to the user
        return( deliver );
    }

    # Object was not within TTL or Grace Period time-frames; return a miss.
    return( miss );

}


sub vcl_synth {
    if (resp.status == 503 && req.http.sie-enabled) {
        unset req.http.sie-enabled;
        return (restart);
    }


}
