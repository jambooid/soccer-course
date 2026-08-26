# We dribbling

在 PS1 和 PS2 时代，*实况足球*（WE / PES）之所以能产生极强的真实操纵感，其核心在于“将球员与足球作为两个独立物理实体处理”**，并引入了**“触球点（Touch Point）与步伐锁死（Animation Lock-in）”的底层逻辑。

如果希望在自己的游戏引擎中复刻或借鉴这一机制，可以从以下**四大技术模块**进行具体落地实现：

### 一、 核心物理与逻辑架构：球球员解耦

绝大多数早期的简单足球游戏是“球员粘球”（足球作为球员手部的子节点挂载）。而 PES/WE 的核心底层是：**球是一个自由运行的物理球体，球员只是通过定期施加脉冲（Impulse）或冲量来“推”球前进。**

#### 1. 带球判定环（Dribble Touch Loop）

- **带球状态机**：当球员处于带球状态时，系统不使用强行物理碰撞，而是每隔一定帧数检测一次“脚与球的距离”。

- **触球条件**：

  $$\text{Distance}(\text{FootPosition}, \text{BallPosition}) \le \text{TouchRadius}$$

  一旦满足条件且处于“可触球帧”（非摆腿动画锁定期），触发一次**带球推球冲量**。

#### 2. 状态分配与速度推球（Dribble Impulse Logic）

在普通跑动、高速冲刺（按住 R1）或精准带球（按住 R2）时，推球的逻辑完全不同：

- **普通带球 (Jog Drive)**：推球力度小，方向容错高。每隔约 `0.3~0.4s` 触球一次，球的推进速度略高于当前球员跑动速度（让球向前滚动），球离脚距离保持在 `0.5m ~ 1.2m`。
- **冲刺带球 (Sprint / R1)**：降低触球频率（如 `0.6~0.8s` 触球一次），增大推球冲量（`Impulse`），球会被踢出 `2.0m ~ 4.0m` 远。这赋予了防守球员“趁球离脚间隙（Out of Control Zone）”断球的机会。
- **精准带球 (Precision / R2)**：高频微小触球（每 `0.15~0.2s` 一次），强行将球的运动速度缩减为与球员脚步同步，球离脚绝不超过 `0.3m`。  

### 二、 动画与力的结合：步伐锁死与转向惯性

PS1/PS2 时代硬件算力有限，无法做复杂的 IK（逆运动学）腿部步幅匹配，WE 使用的是**基于状态机的步幅与转向限制**。

#### 1. 步幅帧锁死（Animation Step Lock-in）

- 球员的奔跑动画会被划分为关键帧点：**左脚触地/触球帧**、**双脚腾空帧**、**右脚触地/触球帧**。
- **指令响应延迟**：玩家按下转向或变向键时，系统**不会立刻改变球员和球的运动矢量**，而是必须等待动画播放到下一个“脚部离地/触球关键帧”。这种“微小但真实的输入延迟（Input Latency）”正是重量感和惯性感的来源。

#### 2. 转向惯性与减速（Turning Resistance）

当玩家在带球中做出大角度转向（如 90 度或 180 度）：

- **小角度转向（< 45度）**：球员在下一次触球时，用外脚背将球向新方向轻推，矢量平滑过渡。
- **大角度急转（> 90度）**：
  1. 触发专用的“急停/变向动画”（Cutback / Hook animation）。
  2. 强行将球员的物理速度矩阵乘以衰减系数（例如 `Velocity = Velocity * 0.3`）。
  3. 球员用脚内侧/脚底将球拉向新方向。如果此时处于冲刺状态（按住 R1），球会因为惯性继续向前滚，而球员转向，导致**带球失误/趟大**。

### 三、 算法与属性介入：动态控制偏差（Stat Influence）

WE/PES 的精髓在于，玩家的输入命令只是“意图”，实际输出结果会被球员属性（Attributes）**和**当前物理状态（Physics State）重构。

Plaintext

```
[玩家输入方向/力度] 
       │
       ▼
[基础推球矢量计算] ───► 叠加属性偏差 (Dribble Accuracy, Dribble Speed)
       │
       ▼
[物理状态修正] ──────► 叠加状态偏差 (当前速度矢量, 身体平衡度 Balance)
       │
       ▼
[最终给球施加的 Impulse 矢量]
```

#### 关键计算公式逻辑（伪代码）：

C#

```
// 计算每次脚触球时给球施加的实际 Impulse 矢量
Vector3 CalculateDribbleImpulse(Player player, Vector3 inputDirection) 
{
    // 1. 基础方向与速度
    Vector3 targetDir = inputDirection.normalized;
    float baseForce = player.IsSprinting ? sprintForce : normalForce;
    
    // 2. 属性影响 (带球精度 Dribble Accuracy, 假设范围 1-99)
    float accuracyRatio = player.stats.dribbleAccuracy / 99.0f;
    
    // 角度偏差：属性越低，推球偏离玩家输入方向的随机夹角越大
    float maxAngleError = Mathf.Lerp(25.0f, 2.0f, accuracyRatio); // 99属性误差仅2度
    Vector3 finalDir = Quaternion.Euler(0, Random.Range(-maxAngleError, maxAngleError), 0) * targetDir;
    
    // 3. 动态状态影响 (身体平衡/跑动速度)
    // 如果球员正在最高速冲刺，或者正在承受防守球员推搡 (Balance 校验)
    float speedPenalty = player.CurrentSpeed / player.MaxSpeed;
    float offsetMagnitude = (1.0f - accuracyRatio) * speedPenalty * maxDistanceDeviation;
    
    // 4. 合成最终给球施加的 Impulse
    Vector3 ballImpulse = finalDir * baseForce + (finalDir * offsetMagnitude);
    return ballImpulse;
}
```

### 四、 特殊带球技巧（Skill Moves）的技术实现

PS1（如 *WE2000*）和 PS2（如 *PES 5/6*）中的特技并非复杂的全物理模拟，而是**脚本化的状态机切换（Scripted State Overrides）**。

#### 1. 假动作 / 剪刀脚假身（Step Over / Body Feint）

- **触发方式**：连续快速按两下 L1 / R2。
- **底层实现**：
  1. 暂停常规带球逻辑，锁定玩家方向输入 0.3 秒。
  2. 播放剪刀脚跨球动画（球的物理速度保留当前惯性直线前滚，不做碰撞处理）。
  3. **AI 预判对抗机制**：在此帧内，向周围防守 AI 发送一个 `TriggerFeintEvent`。若防守者“防守意识（Defense）”属性低，其AI寻路节点（NavMesh/Target）会被强行向假动作方向拉偏 0.5 秒。

#### 2. 扣球变向（Fake Shot Cut / 假射）

- **触发方式**：射门键（Square）+ 短传键（Cross）。
- **底层实现**：
  1. **取消射门状态**：清理射门力量条和射门逻辑队列。
  2. **强制更改球权与方向**：播放急停扣球动画，将球的当前速度矢量瞬间重置（`Ball.Velocity = Player.Forward * CutSpeed`），同时使球员获得一个向侧前方的瞬时位移。

#### 3. 马赛回旋（Marseille Roulette）

- **触发方式**：右摇杆（R3）旋转一圈（PS2 引入）。
- **底层实现**：
  1. 将球临时附加为球员脚部节点的“伪子物体”（Kinematic 模式），强制沿弧线贴脚运动。
  2. 播放旋转动画，在此期间球员的碰撞体（Capsule Collider）获得高优先级的物理推开判定（推开贴身的防守球员）。
  3. 动画结束帧，取消 Kinematic，恢复球的自由刚体（RigidBody）物理。

### 给游戏开发者的复刻建议架构

如果你正准备用 **Unity** 或 **Unreal Engine** 实现类似系统，建议构建以下 3 层架构：

1. **底层（Ball Physics Layer）**：
   - 采用真实的 Sphere Collider + PhysicMaterial（高弹性、适中摩擦力）。
   - 开启连续碰撞检测（Continuous Collision Detection），防止高速穿模。
2. **中层（Player Controller & Touch Trigger）**：
   - 使用 Animation Track / Root Motion 控制球员位移。
   - 在动画里关键的“脚部接触点”帧添加 **Animation Event（动画事件）**，例如 `OnLeftFootTouch()` 或 `OnRightFootTouch()`。
   - 每次触发 Event 时，向球所在的位置发送 Raycast/SphereCast 进行带球推球计算。
3. **顶层（AI & Input Buffering）**：
   - 设置一个短时间（如 `150ms`）的指令缓冲队列（Input Buffer）。当玩家在动画锁定期按下变向或扣球时，指令写入队列，在下一个触球帧立刻响应。  

通过这套“**球体自由物理 + 基于动画帧的低频 Impulse 推进 + 属性驱动的方向/力度误差**”机制，即可在现代引擎中完美重现 PS1/PS2 时代 PES/WE 那种充满操作上限、兼具重量感与操控细腻度（Dribbling Mechanics）的带球手感。