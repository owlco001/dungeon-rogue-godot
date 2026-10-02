extends Node
## EventBus（v0.8 B1）：只声明信号，不含逻辑（02 §4.5 / 07 §2.2）。
## 玩法层 emit → 表现层 listen；表现层禁止 emit 玩法信号。
## fx.gd 是 static 类不能 connect，由 main.gd 或各 listener 自行 connect。

signal enemy_died(enemy: Node2D)                        # enemy.gd _die 转发 died
signal enemy_spawned(enemy: Node2D)                     # 波次出场/精英登场（B6）
signal elite_spawned(pos: Vector2)                      # elite_spawn 音（B5）
signal boss_phase_changed(boss_id: String, phase: int)  # boss.gd phase（B5）
signal boss_died(boss_id: String)                       # boss_die 音（B5）
signal superweapon_synthesized(super_id: String, pos: Vector2)  # 05 附录 A.2：T0 唯一事件源
signal superweapon_burst(pos: Vector2)                  # 05 附录 A.2：T+500 爆发帧
signal relic_gained(relic_id: String, rarity: String)   # rarity ∈ c/r/l（B5）
signal chest_opened(pos: Vector2)                       # 宝箱（B5）
signal enemy_fired(pos: Vector2)                        # spitter 吐酸 play_at/pan（B5）
signal exploder_fuse_start(pos: Vector2)                # 自爆前摇开始（B5）
signal wave_started(n: int, total: int)                 # wave_director（B6）
signal floor_timer_warning(seconds_left: int)           # 层倒计时 ≤10s 起每秒（B6）
signal floor_changed(floor_num: int, theme: String)
signal run_ended(victory: bool, stats: Dictionary)
signal player_damaged(amount: float, from_dir: Vector2, attacker: Node2D)  # attacker 可为 null（环境伤害）
signal player_died()                                    # phoenixheart 钩子（B5）
signal relic_picked(relic_id: String)                   # 拾取爆发（档位色 glow，B5）
signal bgm_duck(active: bool)                           # Boss 层进出 / 超武演出
signal toast_requested(text: String)                    # 替代 hud/lobby 每帧 drain 轮询
signal save_requested()                                 # 关键节点立即写盘（SaveService）
