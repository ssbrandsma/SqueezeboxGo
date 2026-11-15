# jive_alsa patch proposals (WP1, audio-owned)

These are **proposals only**, kept under `audio/alsa/proposals/` per the
WP1 work split. They are NOT applied to any tree: `squeezeplay/` belongs
to Agent 2, and upstream patches land via Agent 2's `squeezeplay/patches/`
flow with Lead review. Base for all diffs: `ralph-irving/squeezeplay@758bc11`.

| # | File | Proposal | Rationale |
|---|---|---|---|
| 1 | `0001-log-negotiated-pcm-params.patch` | `decode_alsa_backend.c`: after `_pcm_open` succeeds, `LOG_INFO` one line with device, format, rate, channels, period/buffer frames | Target bring-up needs the negotiated matrix in logs; today only format+rate are logged, period/buffer sizes are invisible |
| 2 | `0002-clamp-absurd-buffer-params.patch` | `decode_alsa_backend.c` `main()`: clamp `buffer_time` to 5…500 ms and `period_count` to 2…16 with a `LOG_WARN` when clamping | A typo'd `USEALSABUFFERTIME`/`USEALSAPERIODCOUNT` today yields silent misbehavior (XRUN storm or 10 s latency); fail-soft with a visible warning |
| 3 | `0003-audio-owner-hook.patch` | `decode_alsa.c`: before forking playback `jive_alsa`, run `audio-owner acquire squeezeplay --pid <ppid>` when `AUDIO_OWNER_BIN` is set; `release` via `atexit` | Opt-in single-holder integration honoring the interface contract; zero behavior change when the env var is unset |

Status: unreviewed by Agent 2 / Lead. Each patch carries its own
justification header; validation plan is `sh audio/tests/run-all.sh`
(host) + target playback soak.
