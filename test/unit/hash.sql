select '---------- hash.sql --------------------------------------------';
--
-- blob table and hashing
--

/*
select bundle.create_blob ('hi mom');
select results_eq(
    $$ select hash from bundle.blob where value='hi mom' $$,
    $$ select bundle.hash('hi mom')::text; $$,
    'Blob hash of val < 32 chars equals bundle.hash() output.'
);
*/

select bundle.create_blob('this is a very long string that is longer than 32 chars');
select results_eq(
    $$ select hash from bundle.blob where value='this is a very long string that is longer than 32 chars' $$,
    $$ select bundle.hash('this is a very long string that is longer than 32 chars')::text; $$,
    'Blob hash > 32 chars equals hash() output.'
);

select bundle.create_blob('testing');
select results_eq(
    $$ select 'testing'; $$,
    $$ select bundle.unhash(bundle.hash('testing')); $$,
    'Unhash of hashed output equals input value'
);

/*
select results_eq(
    $$ select 'abcdefghijklmnopqrstuvwxyz1234567890'; $$,
    $$ select bundle.unhash(bundle.hash('abcdefghijklmnopqrstuvwxyz1234567890')); $$,
    'Unhash of hashed output equals input value'
);
*/

select is(
    null,
    bundle.unhash(bundle.hash(null)),
    'Unhash of hash of null is null'
);


