# Local Hindsight for VS Code

Hindsight **1.1.0** runs as a Docker service outside the editor, with an image
pinned by digest, embedded PostgreSQL, and a persistent model cache.
The stable worker identity (`hindsight-local`) allows asynchronous operations
to resume after container recreation. Do not run two instances with the same
worker identity against the same database.

## Starting the service

Prerequisites: Docker Compose, `gh auth login` with a Copilot-enabled account,
and Internet access. The first start downloads the image and embedding model;
allow up to 20 minutes. The container is limited to 2500 MiB of memory and 2 CPUs.
The default `gpt-6-luna` model must be available to that account; otherwise,
set `HINDSIGHT_API_LLM_MODEL` in `.env` to an available compatible model.

From the directory containing `compose.yaml`:

```sh
docker compose config --quiet
sh start.sh
docker compose ps
curl -fsS http://127.0.0.1:8888/health
```

- API: <http://127.0.0.1:8888>
- Dashboard: <http://127.0.0.1:9999/dashboard>
- Logs: `docker compose logs --tail 100`.
- Stop while keeping data: `docker compose stop`.
- Start again after a stop: `sh start.sh`. The `unless-stopped` restart policy
  also restarts the service after a reboot unless it was explicitly stopped.
- Do not run `docker compose down --volumes`: it would delete the memories.

Ports can be changed through [.env.example](.env.example); update the MCP URLs
in the affected workspaces as well.

`start.sh` obtains a token with `gh auth token` and passes it only through the
container environment. It does not copy the Copilot home directory, import
plugins or hooks, or write credentials into the project. Alternatively, set
`COPILOT_GITHUB_TOKEN` in the environment. The `gh` and Copilot logins must
refer to the account you intend to use.

The token remains in Docker metadata and in the process environment, where
Docker administrators and root can read it. Do not share `docker inspect` or
`docker compose config` output with credentials exported; use
`docker compose config --quiet`.
After token expiration or revocation, update the login and run
`sh start.sh --force-recreate`. The health check tests the API and database,
not the LLM login.

Git ignores the local `.vscode/mcp.json`, `.env`, `.env.*` (except
`.env.example`), `*.env`, `.envrc`, `secrets/`, common private-key formats,
and `backups/`. Keep only examples, never credentials, in shared templates.
`.gitignore` cannot prevent secrets in tracked files or force-added files:
review the contents before committing or publishing.

## LLM processing and costs

- Fact extraction uses the official `github-copilot` provider and the exact
  `gpt-6-luna` model, with one concurrent request and limited retries.
- Multilingual embeddings run on CPU using
  `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`.
- Local RRF ranking avoids a second neural reranker model.
- Automatic observation consolidation is deliberately **disabled**. Retain
  still extracts facts and recall uses local search; reflect requires additional
  LLM calls and should be used only when needed.
- To enable observations, set `HINDSIGHT_API_ENABLE_OBSERVATIONS=true` in
  `.env` and recreate the service with `sh start.sh`; also check any per-bank
  overrides.
- [.env.example](.env.example) includes optional LLM overrides for retain,
  reflect, and consolidation. Copy it to `.env` if that file does not exist,
  uncomment and set the desired variables, then run `sh start.sh`. If `.env`
  already exists, merge only the desired settings. Commented overrides leave
  the global settings in use. When changing providers, choose a compatible model
  and, if needed, a dedicated URL and credentials. Reasoning-effort support
  depends on the provider and model. Setting a consolidation model does not
  enable observations.

The database and search are local, but **Luna is not**: content sent to retain
or reflect goes to GitHub Copilot. Usage depends on the plan and model; no fixed
credit cost is guaranteed. Avoid full transcripts, secrets, and saving every
message; prefer durable facts in short batches.

## One bank per VS Code project

One Hindsight instance can serve all projects. Give each project a stable,
unique bank ID and its own single-bank MCP endpoint, for example `project-a`
and `project-b`. Avoid using only a directory name that could collide with
another project. One bank per repository is a good default; a monorepo can
share a bank. This setup does not use a shared global bank.

For this workspace:

1. If `.vscode/mcp.json` does not exist, copy the
   [MCP template](.vscode/mcp.example.json):

   ```sh
   cp .vscode/mcp.example.json .vscode/mcp.json
   ```

   If it already exists, merge the `hindsight` server entry manually instead
   of overwriting existing servers.
2. Replace `your-project-bank-id` in the local MCP URL with a stable, unique ID.
   The template is shared; `.vscode/mcp.json` remains local and is ignored by
   Git.
3. Use Copilot in **Agent** mode in VS Code, run **MCP: List Servers**, start
   `hindsight`, and authorize its tools. The editor must approve the MCP
   configuration. The workspace also provides
   [memory instructions](.github/copilot-instructions.md).

Keep the same bank ID after moving or cloning the project or migrating the VM.
Changing the ID in the MCP URL selects another bank; it does not move existing
memories from the old bank.

For another project, the official integration can add the server and rules
without replacing other instructions. This optional method requires `uvx`
(provided by `uv`). From that project's directory:

```sh
uvx --from hindsight-copilot==0.1.0 hindsight-copilot init \
  --api-url http://127.0.0.1:8888 \
  --bank-id project-a
```

The command modifies `.vscode/mcp.json` and `.github/copilot-instructions.md`.
If the existing JSON contains comments, it offers a manual snippet. Review
the generated instructions: avoid hardcoding a personal bank ID, prohibit
storing secrets and transcripts, and reserve reflect for explicit requests, as
in this workspace. To keep the other project's MCP configuration local, ignore
`/.vscode/mcp.json` in that project's Git repository and, if already tracked,
remove it from tracking without deleting the local file. Alternatively, merge
the following entry into `servers` in the project's MCP file:

```json
{
  "hindsight": {
    "type": "http",
    "url": "http://127.0.0.1:8888/mcp/project-a/"
  }
}
```

The first retain creates a missing bank. The instructions guide recall and
retain; **this is not an automatic chat archive**. It does not import past
conversations or guarantee a save on every turn. Tool availability and
instruction adherence depend on the client and agent. With Copilot SDK/CLI in
VS Code, verify that the client imports the workspace MCP servers and actually
exposes the tools; the file alone does not guarantee this. For multi-root
workspaces, prefer separate windows when strictly distinct context is needed.

Banks separate context, but **are not an authorization boundary**: any local
process or user can access this instance through its API and dashboard. Ports
are bound to loopback and there is no application authentication. Do not expose
them to the network without additional protection.

With Remote SSH or a dev container, `127.0.0.1` refers to the environment
running the MCP client, not necessarily the local computer. Provide a tunnel or
a URL reachable from that environment.

## Backup and migration to a VM

Compose volumes: `hindsight-local_pg_data` and `hindsight-local_model_cache`.
The database contains all banks; the cache can be downloaded again. Do not
change the embedding model or dimensions during a straightforward migration.

For a consistent physical copy, stop the service before backing it up. These
commands create a private archive and restart using the token already present
in the container metadata:

```sh
mkdir -p backups
chmod 700 backups
docker compose stop
docker run --rm \
  -v hindsight-local_pg_data:/data:ro \
  --entrypoint tar ghcr.io/vectorize-io/hindsight:1.1.0@sha256:50311d02b4d5d2b7c5242bd336edf8735df8374eaad496a92f49c83b37d2aa06 \
  -C /data -czf - . > backups/pg_data.tar.gz
chmod 600 backups/pg_data.tar.gz
docker compose start --wait --wait-timeout 1200
```

If the backup fails, do not proceed with migration; restart the service. Do not
commit or share archives: they contain the memories.

On the VM, initially use the **same version** of Hindsight and an architecture
compatible with PostgreSQL:

1. Copy the Compose configuration and archive over SSH; do not copy the Copilot
   token.
2. Configure the future provider in `.env` (see [.env.example](.env.example)).
   For an OpenAI-compatible provider, set `openai`, the model, base URL, and
   API key. Protect `.env` with permissions `600`. `start.sh` is intended for
   local Copilot login; on a VM using another provider, run Docker Compose
   directly.
3. Run `docker compose create` to create the container and volumes without
   starting them.
4. With the service stopped, restore **only to a new, empty volume**:

   ```sh
   docker run --rm -i \
     -v hindsight-local_pg_data:/data \
     --entrypoint tar ghcr.io/vectorize-io/hindsight:1.1.0@sha256:50311d02b4d5d2b7c5242bd336edf8735df8374eaad496a92f49c83b37d2aa06 \
     -C /data -xzf - < backups/pg_data.tar.gz
   docker compose up -d --wait --wait-timeout 1200
   ```

5. Before cutover, check health, list the banks, and recall a known memory.
6. Expose the service through a VPN or authenticated reverse proxy, or keep it
   bound to loopback and use an SSH tunnel without changing the bank IDs:

   ```sh
   ssh -N -L 8888:127.0.0.1:8888 -L 9999:127.0.0.1:9999 user@vm
   ```

With the tunnel active and the local service stopped, MCP URLs stay unchanged.
For a different architecture, use a logical PostgreSQL dump and restore instead.

## Checks performed

- API health, database connection, and dashboard HTTP 200.
- SDK authentication in the container and exact `gpt-6-luna` availability.
- Retain of a synthetic Italian document and recall through REST and MCP.
- Single-bank MCP endpoint without a bank selector in the tools; the test
  project's result was not recalled from a second, empty bank.
- The same memory UUID and content after container recreation.
- Consolidation disabled in the bank configuration.
- Synthetic test banks removed after verification.

Observed idle memory usage was about 1.5 GiB, not a guarantee under load.
VM cutover has not been verified. MCP tool activation requires approval in
the editor.

## References

- [Hindsight MCP](https://hindsight.vectorize.io/developer/mcp-server)
- [Official GitHub Copilot integration](https://github.com/vectorize-io/hindsight/tree/v1.1.0/hindsight-integrations/github-copilot)
