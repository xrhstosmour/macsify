# Security

## Shell Command Safety

- Managed machines often run endpoint monitoring that flags command patterns resembling attacker tradecraft, and a benign one-liner can trigger a hard network lockout. Use the most transparent, inspectable form of a command, never the most compact or clever one.
- Never run network reconnaissance tools (`nc`, `nmap`, `tcpdump`), or set up reverse shells and tunnels (`/dev/tcp` redirects, `socat`, interpreter-driven socket connections), unless the task is explicit, authorized security testing.
- Prefer a dedicated edit tool over in-place file rewriting one-liners (`sed -i`, rewriting through `awk`/`perl` pipelines) or code execution embedded inside a text processor. These read as obfuscation to automated monitoring even when the intent is harmless.
- Don't chain unrelated operations into one compound command with `&&`, `;`, or command substitution to save a round trip. Single-purpose commands are independently reviewable and less likely to match a multi-stage attack signature.
- Get explicit user approval before touching credential storage (`~/.ssh`, `~/.aws`, `~/.kube`), system configuration (`/etc/`), or security tooling, even for read access.
- If a command gets blocked or flagged, stop. Don't retry with obfuscation or an encoding trick to get around the block. Surface the block to the user and ask how to proceed.
