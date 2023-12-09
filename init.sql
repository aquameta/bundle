------------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------------

/*
create extension if not exists hstore schema public;
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto schema public;

create extension if not exists meta;
create extension if not exists meta_triggers;
*/

drop schema if exists delta cascade;
create schema delta;
set search_path=delta;
