# Bundle Sync Architecture - 2025-11-05

## Overview

Bundle sync enables git-like push/pull/clone operations between Aquameta instances. The architecture supports multiple transports (HTTP, WebRTC, SSH) with shared protocol logic.

## Design Principles

1. **Transport-agnostic protocol** - Same sync logic regardless of transport
2. **Daemon-based client** - All network IO happens in the daemon
3. **Database-driven logic** - Protocol operations defined in SQL
4. **NOTIFY for signaling only** - Daemon queries DB for actual payload data
5. **Content-addressed storage** - SHA256 hashes enable efficient sync

## Architecture Layers

```
┌─────────────────────────────────────────────────┐
│  SQL Functions (bundle.push/pull/clone)         │
│  - Write to sync_queue table                    │
│  - NOTIFY daemon via pg_notify()                │
└─────────────────────────────────────────────────┘
                      ↓ pg_notify (signal only)
┌─────────────────────────────────────────────────┐
│  Daemon Listener (dedicated goroutine)          │
│  - LISTEN on dedicated connection               │
│  - Spawn handler goroutine per notification     │
└─────────────────────────────────────────────────┘
                      ↓ spawn goroutine
┌─────────────────────────────────────────────────┐
│  Handler Goroutine (non-blocking)               │
│  - Query DB for queue entry                     │
│  - Execute transport operation                  │
│  - Update status in DB                          │
└─────────────────────────────────────────────────┘
                      ↓ transport
┌─────────────────────────────────────────────────┐
│  Remote Instance                                │
│  - HTTP: /endpoint/db/                          │
│  - WebRTC: peer connection                      │
│  - SSH: git-like protocol                       │
└─────────────────────────────────────────────────┘
```

## Communication Pattern

### PostgreSQL → Daemon (NOTIFY/LISTEN)

#### SQL Side: Queue + Signal

```sql
create table bundle.sync_queue (
    id uuid primary key default public.uuid_generate_v4(),
    action text not null check (action in ('push', 'pull', 'clone')),
    repository_id uuid not null references bundle.repository(id),
    remote_id uuid not null references bundle.remote(id),
    options jsonb default '{}',
    status text not null default 'pending' check (status in ('pending', 'running', 'completed', 'failed')),
    error_message text,
    created_at timestamp not null default now(),
    started_at timestamp,
    completed_at timestamp
);

create or replace function bundle.push(
    remote_name text,
    repository_name text,
    options jsonb default '{}'
) returns uuid as $$
declare
    repo_id uuid;
    remote_id uuid;
    queue_id uuid;
begin
    -- Get repository and remote IDs
    select id into repo_id
    from bundle.repository
    where name = repository_name;

    if repo_id is null then
        raise exception 'Repository not found: %', repository_name;
    end if;

    select id into remote_id
    from bundle.remote
    where name = remote_name;

    if remote_id is null then
        raise exception 'Remote not found: %', remote_name;
    end if;

    -- Add to queue
    insert into bundle.sync_queue (action, repository_id, remote_id, options)
    values ('push', repo_id, remote_id, options)
    returning id into queue_id;

    -- Signal daemon (just the queue ID, no payload data)
    perform pg_notify('bundle_sync', queue_id::text);

    return queue_id;
end;
$$ language plpgsql;
```

#### Daemon Side: Listen + Handle

```go
package bundle

import (
    "context"
    "encoding/json"
    "github.com/google/uuid"
    "github.com/jackc/pgx/v5/pgxpool"
)

// SyncListener manages the NOTIFY/LISTEN loop
type SyncListener struct {
    pool *pgxpool.Pool  // Main connection pool for work
    handler *SyncHandler
}

// Start begins listening for sync notifications
func (l *SyncListener) Start(ctx context.Context) error {
    // Dedicated connection for LISTEN (separate from pool)
    conn, err := l.pool.Acquire(ctx)
    if err != nil {
        return err
    }
    defer conn.Release()

    // Start listening
    _, err = conn.Exec(ctx, "LISTEN bundle_sync")
    if err != nil {
        return err
    }

    // Listener loop (runs in its own goroutine)
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        default:
            // Block waiting for notification
            notification, err := conn.Conn().WaitForNotification(ctx)
            if err != nil {
                return err
            }

            // Parse queue ID from notification
            queueID, err := uuid.Parse(notification.Payload)
            if err != nil {
                continue // Invalid payload, skip
            }

            // Spawn handler goroutine (non-blocking)
            go l.handler.HandleSync(context.Background(), queueID)
        }
    }
}

// SyncHandler processes sync operations
type SyncHandler struct {
    pool *pgxpool.Pool
    transports map[string]Transport
}

// HandleSync processes a single sync queue entry
func (h *SyncHandler) HandleSync(ctx context.Context, queueID uuid.UUID) {
    // Query DB for queue entry details
    var entry SyncQueueEntry
    err := h.pool.QueryRow(ctx, `
        select q.id, q.action, q.repository_id, q.remote_id, q.options,
               r.name as repository_name,
               rm.name as remote_name, rm.transport, rm.url, rm.config
        from bundle.sync_queue q
        join bundle.repository r on q.repository_id = r.id
        join bundle.remote rm on q.remote_id = rm.id
        where q.id = $1 and q.status = 'pending'
    `, queueID).Scan(
        &entry.ID, &entry.Action, &entry.RepositoryID, &entry.RemoteID, &entry.Options,
        &entry.RepositoryName, &entry.RemoteName, &entry.Transport, &entry.URL, &entry.Config,
    )
    if err != nil {
        return // Already processed or not found
    }

    // Mark as running
    h.pool.Exec(ctx, `
        update bundle.sync_queue
        set status = 'running', started_at = now()
        where id = $1
    `, queueID)

    // Get transport
    transport := h.transports[entry.Transport]
    if transport == nil {
        h.markFailed(ctx, queueID, "unknown transport: "+entry.Transport)
        return
    }

    // Execute sync operation
    var err error
    switch entry.Action {
    case "push":
        err = h.executePush(ctx, entry, transport)
    case "pull":
        err = h.executePull(ctx, entry, transport)
    case "clone":
        err = h.executeClone(ctx, entry, transport)
    }

    // Update status
    if err != nil {
        h.markFailed(ctx, queueID, err.Error())
    } else {
        h.markCompleted(ctx, queueID)
    }
}

func (h *SyncHandler) markFailed(ctx context.Context, queueID uuid.UUID, errMsg string) {
    h.pool.Exec(ctx, `
        update bundle.sync_queue
        set status = 'failed', error_message = $2, completed_at = now()
        where id = $1
    `, queueID, errMsg)
}

func (h *SyncHandler) markCompleted(ctx context.Context, queueID uuid.UUID) {
    h.pool.Exec(ctx, `
        update bundle.sync_queue
        set status = 'completed', completed_at = now()
        where id = $1
    `, queueID)
}

type SyncQueueEntry struct {
    ID             uuid.UUID
    Action         string
    RepositoryID   uuid.UUID
    RemoteID       uuid.UUID
    Options        map[string]interface{}
    RepositoryName string
    RemoteName     string
    Transport      string
    URL            string
    Config         map[string]interface{}
}
```

## Data Structures

### Remote Configuration

```sql
create table bundle.remote (
    id uuid primary key default public.uuid_generate_v4(),
    name text not null unique,
    transport text not null check (transport in ('http', 'webrtc', 'ssh')),
    url text not null,
    config jsonb default '{}'
);
```

### Sync State Tracking

```sql
create table bundle.sync_state (
    id uuid primary key default public.uuid_generate_v4(),
    repository_id uuid references bundle.repository(id),
    remote_id uuid references bundle.remote(id),
    last_sync timestamp,
    last_push_commit uuid references bundle.commit(id),
    last_pull_commit uuid references bundle.commit(id),
    unique(repository_id, remote_id)
);
```

## Transport Abstraction

### Go Interface

```go
type Transport interface {
    // Negotiate determines what commits/blobs need syncing
    Negotiate(ctx context.Context, local, remote RepositoryRef) (*SyncPlan, error)

    // PushCommits sends commits to remote
    PushCommits(ctx context.Context, commits []Commit) error

    // PushBlobs sends blob content to remote
    PushBlobs(ctx context.Context, blobs []Blob) error

    // PullCommits fetches commits from remote
    PullCommits(ctx context.Context, commitIDs []uuid.UUID) ([]Commit, error)

    // PullBlobs fetches blob content from remote
    PullBlobs(ctx context.Context, hashes []string) ([]Blob, error)
}

type RepositoryRef struct {
    Name string
    ID   uuid.UUID
}

type SyncPlan struct {
    CommitsToPush []uuid.UUID
    CommitsToPull []uuid.UUID
    BlobsToPush   []string  // SHA256 hashes
    BlobsToPull   []string
}

type Commit struct {
    ID             uuid.UUID
    RepositoryID   uuid.UUID
    Message        string
    ParentCommitID *uuid.UUID
    Time           time.Time
    JSONBFields    map[string]interface{}
}

type Blob struct {
    Hash  string  // SHA256
    Value string
}
```

### HTTP Transport

Uses existing endpoint REST API:

```go
type HTTPTransport struct {
    baseURL string
    client  *http.Client
}

func (t *HTTPTransport) PullCommits(ctx context.Context, commitIDs []uuid.UUID) ([]Commit, error) {
    // Convert UUIDs to comma-separated string
    ids := make([]string, len(commitIDs))
    for i, id := range commitIDs {
        ids[i] = id.String()
    }

    // GET /endpoint/db/rows/bundle/commit?id=in.(uuid1,uuid2,...)
    url := fmt.Sprintf("%s/endpoint/db/rows/bundle/commit?id=in.(%s)",
        t.baseURL, strings.Join(ids, ","))

    resp, err := t.client.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var commits []Commit
    err = json.NewDecoder(resp.Body).Decode(&commits)
    return commits, err
}

func (t *HTTPTransport) PushCommits(ctx context.Context, commits []Commit) error {
    // POST /endpoint/db/rows/bundle/commit
    body, err := json.Marshal(commits)
    if err != nil {
        return err
    }

    resp, err := t.client.Post(
        t.baseURL+"/endpoint/db/rows/bundle/commit",
        "application/json",
        bytes.NewReader(body),
    )
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != 201 {
        return fmt.Errorf("push failed: %s", resp.Status)
    }
    return nil
}

func (t *HTTPTransport) PushBlobs(ctx context.Context, blobs []Blob) error {
    // POST /endpoint/db/rows/bundle/blob
    body, err := json.Marshal(blobs)
    if err != nil {
        return err
    }

    resp, err := t.client.Post(
        t.baseURL+"/endpoint/db/rows/bundle/blob",
        "application/json",
        bytes.NewReader(body),
    )
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != 201 {
        return fmt.Errorf("push failed: %s", resp.Status)
    }
    return nil
}

func (t *HTTPTransport) PullBlobs(ctx context.Context, hashes []string) ([]Blob, error) {
    // GET /endpoint/db/rows/bundle/blob?hash=in.(hash1,hash2,...)
    url := fmt.Sprintf("%s/endpoint/db/rows/bundle/blob?hash=in.(%s)",
        t.baseURL, strings.Join(hashes, ","))

    resp, err := t.client.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var blobs []Blob
    err = json.NewDecoder(resp.Body).Decode(&blobs)
    return blobs, err
}

func (t *HTTPTransport) Negotiate(ctx context.Context, local, remote RepositoryRef) (*SyncPlan, error) {
    // Get all local commit IDs
    localCommits, err := getLocalCommits(ctx, local.ID)
    if err != nil {
        return nil, err
    }

    // Get all remote commit IDs
    url := fmt.Sprintf("%s/endpoint/db/rows/bundle/commit?repository_id=eq.%s&select=id",
        t.baseURL, remote.ID)
    resp, err := t.client.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var remoteCommits []struct{ ID uuid.UUID }
    json.NewDecoder(resp.Body).Decode(&remoteCommits)

    // Calculate diff
    plan := &SyncPlan{}
    remoteSet := make(map[uuid.UUID]bool)
    for _, c := range remoteCommits {
        remoteSet[c.ID] = true
    }

    for _, localID := range localCommits {
        if !remoteSet[localID] {
            plan.CommitsToPush = append(plan.CommitsToPush, localID)
        }
    }

    localSet := make(map[uuid.UUID]bool)
    for _, id := range localCommits {
        localSet[id] = true
    }

    for _, remoteCommit := range remoteCommits {
        if !localSet[remoteCommit.ID] {
            plan.CommitsToPull = append(plan.CommitsToPull, remoteCommit.ID)
        }
    }

    // TODO: Calculate blob diffs based on commits
    return plan, nil
}
```

### WebRTC Transport

P2P connection between daemons:

```go
type WebRTCTransport struct {
    peerConnection *webrtc.PeerConnection
    dataChannel    *webrtc.DataChannel
    responseChan   chan Message
}

type Message struct {
    Type string          `json:"type"`
    Data json.RawMessage `json:"data"`
}

func (t *WebRTCTransport) PushCommits(ctx context.Context, commits []Commit) error {
    data, _ := json.Marshal(commits)
    msg := Message{Type: "push_commits", Data: data}
    payload, _ := json.Marshal(msg)

    err := t.dataChannel.SendText(string(payload))
    if err != nil {
        return err
    }

    // Wait for acknowledgment
    select {
    case response := <-t.responseChan:
        if response.Type == "ack" {
            return nil
        }
        return fmt.Errorf("push failed: %s", response.Type)
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

### SSH Transport

Git-like protocol over SSH:

```go
type SSHTransport struct {
    client  *ssh.Client
    baseCmd string // e.g., "aquameta-receive-pack"
}

func (t *SSHTransport) PushCommits(ctx context.Context, commits []Commit) error {
    session, err := t.client.NewSession()
    if err != nil {
        return err
    }
    defer session.Close()

    stdin, _ := session.StdinPipe()
    stdout, _ := session.StdoutPipe()

    // Start remote command
    err = session.Start(t.baseCmd + " push-commits")
    if err != nil {
        return err
    }

    // Send commits as JSON
    encoder := json.NewEncoder(stdin)
    err = encoder.Encode(commits)
    stdin.Close()

    // Read response
    var result struct {
        Status string `json:"status"`
        Error  string `json:"error"`
    }
    json.NewDecoder(stdout).Decode(&result)

    if result.Status != "ok" {
        return fmt.Errorf("push failed: %s", result.Error)
    }

    return session.Wait()
}
```

## Sync Algorithm

### Push Operation

```go
func (h *SyncHandler) executePush(ctx context.Context, entry SyncQueueEntry, transport Transport) error {
    // 1. Negotiate with remote
    localRef := RepositoryRef{Name: entry.RepositoryName, ID: entry.RepositoryID}
    remoteRef := RepositoryRef{Name: entry.RepositoryName, ID: entry.RepositoryID}

    plan, err := transport.Negotiate(ctx, localRef, remoteRef)
    if err != nil {
        return err
    }

    if len(plan.CommitsToPush) == 0 {
        return nil // Nothing to push
    }

    // 2. Get commits from DB
    commits, err := h.getCommits(ctx, plan.CommitsToPush)
    if err != nil {
        return err
    }

    // 3. Push commits
    err = transport.PushCommits(ctx, commits)
    if err != nil {
        return err
    }

    // 4. Get blobs referenced by commits
    blobs, err := h.getBlobs(ctx, plan.BlobsToPush)
    if err != nil {
        return err
    }

    // 5. Push blobs
    err = transport.PushBlobs(ctx, blobs)
    if err != nil {
        return err
    }

    // 6. Update sync state
    return h.updateSyncState(ctx, entry.RepositoryID, entry.RemoteID, commits[len(commits)-1].ID, "push")
}
```

### Pull Operation

```go
func (h *SyncHandler) executePull(ctx context.Context, entry SyncQueueEntry, transport Transport) error {
    // 1. Negotiate with remote
    localRef := RepositoryRef{Name: entry.RepositoryName, ID: entry.RepositoryID}
    remoteRef := RepositoryRef{Name: entry.RepositoryName, ID: entry.RepositoryID}

    plan, err := transport.Negotiate(ctx, localRef, remoteRef)
    if err != nil {
        return err
    }

    if len(plan.CommitsToPull) == 0 {
        return nil // Nothing to pull
    }

    // 2. Pull commits from remote
    commits, err := transport.PullCommits(ctx, plan.CommitsToPull)
    if err != nil {
        return err
    }

    // 3. Insert commits into local DB
    err = h.insertCommits(ctx, commits)
    if err != nil {
        return err
    }

    // 4. Pull blobs
    blobs, err := transport.PullBlobs(ctx, plan.BlobsToPull)
    if err != nil {
        return err
    }

    // 5. Insert blobs into local DB
    err = h.insertBlobs(ctx, blobs)
    if err != nil {
        return err
    }

    // 6. Update sync state
    return h.updateSyncState(ctx, entry.RepositoryID, entry.RemoteID, commits[len(commits)-1].ID, "pull")
}
```

### Clone Operation

```go
func (h *SyncHandler) executeClone(ctx context.Context, entry SyncQueueEntry, transport Transport) error {
    // 1. Create local repository
    repoID, err := h.createRepository(ctx, entry.RepositoryName)
    if err != nil {
        return err
    }

    // 2. Pull all commits from remote
    // (Similar to pull, but pulls everything)

    // 3. Set HEAD to remote's HEAD
    err = h.setHead(ctx, repoID, remoteHeadCommitID)
    if err != nil {
        return err
    }

    // 4. Optionally checkout HEAD
    if entry.Options["checkout"] == true {
        return h.checkoutHead(ctx, repoID)
    }

    return nil
}
```

## Implementation Phases

### Phase 1: Foundation
- [ ] Add remote table to repository.sql
- [ ] Add sync_queue table to repository.sql
- [ ] Add sync_state table to repository.sql
- [ ] Implement NOTIFY/LISTEN in daemon
- [ ] Create transport interface in Go

### Phase 2: HTTP Transport
- [ ] Implement HTTP transport using endpoint
- [ ] Implement push/pull/clone SQL functions
- [ ] Test HTTP sync between instances

### Phase 3: WebRTC Transport
- [ ] Integrate Pion WebRTC library
- [ ] Implement peer discovery
- [ ] Implement WebRTC transport
- [ ] Test P2P sync

### Phase 4: SSH Transport
- [ ] Implement SSH transport
- [ ] Implement git-like protocol
- [ ] Test SSH sync

## Security Considerations

1. **Authentication** - Each transport handles auth differently
   - HTTP: Bearer tokens, API keys in config
   - WebRTC: DTLS, SRTP
   - SSH: Public key authentication
2. **Authorization** - Check permissions before push/pull
3. **Validation** - Verify commit integrity, blob hashes
4. **Rate Limiting** - Prevent abuse via sync_queue status

## Future Enhancements

1. **Partial clone** - Shallow clones, blob filtering
2. **Delta compression** - Pack files for efficient transfer
3. **Resume capability** - Handle interrupted syncs via sync_queue
4. **Conflict resolution** - Merge strategies for diverged histories
5. **Peer discovery** - mDNS, DHT for finding WebRTC peers
