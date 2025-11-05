------------------------------------------------------------------------------
-- REMOTE REPOSITORIES
------------------------------------------------------------------------------

--
-- remote_http
-- HTTP/HTTPS remote repositories (uses endpoint REST API)
--

create table remote_http (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null unique check(name != ''),
    url text not null check(url != ''),
    headers jsonb default '{}'  -- auth tokens, api keys, etc
);


--
-- remote_ssh
-- SSH remote repositories (git-like protocol)
--

create table remote_ssh (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null unique check(name != ''),
    host text not null check(host != ''),
    port integer not null default 22,
    username text not null check(username != ''),
    path text not null default '/',
    key_file text  -- path to private key, or null to use agent
);


--
-- remote_webrtc
-- WebRTC peer-to-peer remote repositories
--

create table remote_webrtc (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null unique check(name != ''),
    peer_id text not null check(peer_id != ''),
    signaling_server text,  -- websocket url for signaling
    ice_servers jsonb default '[]'  -- STUN/TURN servers
);


--
-- remote
-- Unified view of all remote types
--

create view remote as
    select
        id,
        name,
        'http' as transport,
        jsonb_build_object(
            'url', url,
            'headers', headers
        ) as config
    from remote_http

    union all

    select
        id,
        name,
        'ssh' as transport,
        jsonb_build_object(
            'host', host,
            'port', port,
            'username', username,
            'path', path,
            'key_file', key_file
        ) as config
    from remote_ssh

    union all

    select
        id,
        name,
        'webrtc' as transport,
        jsonb_build_object(
            'peer_id', peer_id,
            'signaling_server', signaling_server,
            'ice_servers', ice_servers
        ) as config
    from remote_webrtc;
