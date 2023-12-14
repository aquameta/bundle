------------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------------

create extension if not exists hstore schema public;
create extension if not exists "pg_uuidv7" schema public;
create extension if not exists pgcrypto schema public;

create extension if not exists meta version '0.5.0';
create extension if not exists meta_triggers;

begin;

create schema delta;
set search_path=delta;
