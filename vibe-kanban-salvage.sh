#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE_APP_DIR="${1:-/Users/matrix/Library/Application Support/ai.bloop.vibe-kanban}"
TARGET_HOME="${2:-$ROOT_DIR/.vk-home-migrated}"
TEMPLATE_HOME="${TEMPLATE_HOME:-$ROOT_DIR/.vk-home}"

SOURCE_DB="$SOURCE_APP_DIR/db.sqlite"
TARGET_APP_DIR="$TARGET_HOME/Library/Application Support/ai.bloop.vibe-kanban"
TARGET_DB="$TARGET_APP_DIR/db.v2.sqlite"
TEMPLATE_APP_DIR="$TEMPLATE_HOME/Library/Application Support/ai.bloop.vibe-kanban"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DB" ]]; then
  echo "Source database not found: $SOURCE_DB" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_APP_DIR/db.v2.sqlite" ]]; then
  echo "Template db.v2.sqlite not found: $TEMPLATE_APP_DIR/db.v2.sqlite" >&2
  echo "Create a clean home once first, for example:" >&2
  echo "  HOME=\"$TEMPLATE_HOME\" npx vibe-kanban" >&2
  exit 1
fi

rm -rf "$TARGET_HOME"
mkdir -p "$TARGET_APP_DIR"
cp -R "$TEMPLATE_APP_DIR/." "$TARGET_APP_DIR/"

if [[ -f "$SOURCE_APP_DIR/config.json" ]]; then
  cp "$SOURCE_APP_DIR/config.json" "$TARGET_APP_DIR/config.json"
fi

if [[ -f "$SOURCE_APP_DIR/profiles.json" ]]; then
  cp "$SOURCE_APP_DIR/profiles.json" "$TARGET_APP_DIR/profiles.json"
fi

sqlite3 "$TARGET_DB" <<SQL
ATTACH DATABASE '$SOURCE_DB' AS old;
PRAGMA foreign_keys = OFF;
BEGIN;

DELETE FROM execution_process_logs;
DELETE FROM coding_agent_turns;
DELETE FROM execution_process_repo_states;
DELETE FROM workspace_repos;
DELETE FROM sessions;
DELETE FROM workspaces;
DELETE FROM task_attachments;
DELETE FROM attachments;
DELETE FROM merges;
DELETE FROM tasks;
DELETE FROM project_repos;
DELETE FROM repos;
DELETE FROM projects;
DELETE FROM tags;

INSERT INTO projects (
  id,
  name,
  remote_project_id,
  created_at,
  updated_at,
  default_agent_working_dir
)
SELECT
  id,
  name,
  remote_project_id,
  created_at,
  updated_at,
  ''
FROM old.projects;

INSERT INTO repos (
  id,
  path,
  name,
  display_name,
  created_at,
  updated_at,
  setup_script,
  cleanup_script,
  copy_files,
  parallel_setup_script,
  dev_server_script,
  default_target_branch,
  default_working_dir,
  archive_script
)
SELECT
  id,
  git_repo_path,
  name,
  name,
  created_at,
  updated_at,
  NULLIF(setup_script, ''),
  NULLIF(cleanup_script, ''),
  NULLIF(copy_files, ''),
  0,
  NULLIF(dev_script, ''),
  'main',
  NULL,
  NULL
FROM old.projects;

INSERT INTO project_repos (
  id,
  project_id,
  repo_id
)
SELECT
  id,
  id,
  id
FROM old.projects;

INSERT INTO workspaces (
  id,
  task_id,
  container_ref,
  branch,
  setup_completed_at,
  created_at,
  updated_at,
  archived,
  pinned,
  name,
  worktree_deleted
)
SELECT
  id,
  task_id,
  container_ref,
  branch,
  setup_completed_at,
  created_at,
  updated_at,
  0,
  0,
  NULL,
  COALESCE(worktree_deleted, 0)
FROM old.task_attempts;

INSERT INTO tasks (
  id,
  project_id,
  title,
  description,
  status,
  created_at,
  updated_at,
  parent_workspace_id
)
SELECT
  id,
  project_id,
  title,
  description,
  status,
  created_at,
  updated_at,
  parent_task_attempt
FROM old.tasks;

INSERT INTO workspace_repos (
  id,
  workspace_id,
  repo_id,
  target_branch,
  created_at,
  updated_at
)
SELECT
  ta.id,
  ta.id,
  t.project_id,
  COALESCE(NULLIF(ta.target_branch, ''), 'main'),
  ta.created_at,
  ta.updated_at
FROM old.task_attempts ta
JOIN old.tasks t ON t.id = ta.task_id;

INSERT INTO sessions (
  id,
  workspace_id,
  executor,
  created_at,
  updated_at,
  agent_working_dir,
  name
)
SELECT
  id,
  id,
  executor,
  created_at,
  updated_at,
  NULL,
  NULL
FROM old.task_attempts;

INSERT INTO execution_processes (
  id,
  session_id,
  executor_action,
  status,
  exit_code,
  dropped,
  started_at,
  completed_at,
  created_at,
  updated_at,
  run_reason
)
SELECT
  ep.id,
  ep.task_attempt_id,
  CASE
    WHEN ep.executor_action = '' THEN '{}'
    ELSE ep.executor_action
  END,
  ep.status,
  ep.exit_code,
  COALESCE(ep.dropped, 0),
  ep.started_at,
  ep.completed_at,
  ep.created_at,
  ep.updated_at,
  CASE
    WHEN ep.run_reason IN ('cleanupscript', 'archivescript', 'codingagent', 'devserver') THEN ep.run_reason
    ELSE 'setupscript'
  END
FROM old.execution_processes ep;

INSERT INTO coding_agent_turns (
  id,
  execution_process_id,
  agent_session_id,
  prompt,
  summary,
  created_at,
  updated_at,
  seen,
  agent_message_id
)
SELECT
  id,
  execution_process_id,
  NULLIF(session_id, ''),
  NULLIF(prompt, ''),
  NULLIF(summary, ''),
  created_at,
  updated_at,
  0,
  NULL
FROM old.executor_sessions;

INSERT INTO execution_process_repo_states (
  id,
  execution_process_id,
  repo_id,
  before_head_commit,
  after_head_commit,
  merge_commit,
  created_at,
  updated_at
)
SELECT
  ep.id,
  ep.id,
  t.project_id,
  ep.before_head_commit,
  ep.after_head_commit,
  NULL,
  ep.created_at,
  ep.updated_at
FROM old.execution_processes ep
JOIN old.task_attempts ta ON ta.id = ep.task_attempt_id
JOIN old.tasks t ON t.id = ta.task_id;

INSERT INTO execution_process_logs (
  execution_id,
  logs,
  byte_size,
  inserted_at
)
SELECT
  execution_id,
  logs,
  byte_size,
  inserted_at
FROM old.execution_process_logs;

INSERT INTO attachments (
  id,
  file_path,
  original_name,
  mime_type,
  size_bytes,
  hash,
  created_at,
  updated_at
)
SELECT
  id,
  file_path,
  original_name,
  mime_type,
  size_bytes,
  hash,
  created_at,
  updated_at
FROM old.images;

INSERT INTO task_attachments (
  id,
  task_id,
  attachment_id,
  created_at
)
SELECT
  id,
  task_id,
  image_id,
  created_at
FROM old.task_images;

INSERT INTO merges (
  id,
  workspace_id,
  merge_type,
  merge_commit,
  pr_number,
  pr_url,
  pr_status,
  pr_merged_at,
  pr_merge_commit_sha,
  created_at,
  target_branch_name,
  repo_id
)
SELECT
  m.id,
  m.task_attempt_id,
  m.merge_type,
  m.merge_commit,
  m.pr_number,
  m.pr_url,
  m.pr_status,
  m.pr_merged_at,
  m.pr_merge_commit_sha,
  m.created_at,
  COALESCE(NULLIF(ta.target_branch, ''), 'main'),
  t.project_id
FROM old.merges m
JOIN old.task_attempts ta ON ta.id = m.task_attempt_id
JOIN old.tasks t ON t.id = ta.task_id;

INSERT INTO tags (
  id,
  tag_name,
  content,
  created_at,
  updated_at
)
SELECT
  id,
  tag_name,
  content,
  created_at,
  updated_at
FROM old.tags;

COMMIT;
PRAGMA foreign_keys = ON;
DETACH DATABASE old;
VACUUM;
SQL

echo "Migrated home created at: $TARGET_HOME"
echo "Start with:"
echo "  HOME=\"$TARGET_HOME\" npx vibe-kanban"
