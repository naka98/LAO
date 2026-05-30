import { ChildProcess } from 'child_process';

export type TaskPriority = 'high' | 'medium' | 'low';

export interface QueuedTask {
  id: string;
  priority: TaskPriority;
  category: 'inference' | 'mockup' | 'build';
  run: (taskRef: { setProcess: (proc: ChildProcess) => void }) => Promise<any>;
  resolve: (value: any) => void;
  reject: (reason: any) => void;
  timeoutMs: number;
}

export class SpawnQueueManager {
  private static instance: SpawnQueueManager;
  private queue: QueuedTask[] = [];
  private activeCount = 0;
  private maxConcurrency = 2; // macOS 전체 자원 보호를 위해 동시 실행 2개로 제약

  private constructor() {
    console.log('[LAO Scheduler] Initialized SpawnQueueManager with maxConcurrency = 2');
  }

  public static getInstance(): SpawnQueueManager {
    if (!SpawnQueueManager.instance) {
      SpawnQueueManager.instance = new SpawnQueueManager();
    }
    return SpawnQueueManager.instance;
  }

  /**
   * 태스크를 큐에 등록하고 실행을 대기합니다.
   */
  public enqueue<T>(
    category: 'inference' | 'mockup' | 'build',
    priority: TaskPriority,
    taskFn: (taskRef: { setProcess: (proc: ChildProcess) => void }) => Promise<T>,
    timeoutMs: number = 90000 // 기본 타임아웃 90초 (90,000ms)
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      const task: QueuedTask = {
        id: Math.random().toString(36).substring(7),
        priority,
        category,
        run: taskFn,
        resolve,
        reject,
        timeoutMs
      };

      // 중복 작업 제거 (Deduplication): mockup 카테고리가 대기 중일 때 최신 mockup 요청이 오면 기존 pending mockup은 추방(Evict)
      if (category === 'mockup') {
        this.evictPendingTasks('mockup');
      }

      this.queue.push(task);
      this.sortQueue();
      this.processNext();
    });
  }

  /**
   * 특정 카테고리의 대기 중인 모든 작업을 큐에서 제외하고 reject 처리합니다.
   */
  private evictPendingTasks(category: string) {
    const originalLength = this.queue.length;
    this.queue = this.queue.filter((t) => {
      if (t.category === category) {
        console.log(`[LAO Scheduler] Evicting outdated pending task [ID: ${t.id}] of category "${category}"`);
        t.reject(new Error(`Superseded by a newer task of category: ${category}`));
        return false;
      }
      return true;
    });
    
    if (this.queue.length < originalLength) {
      console.log(`[LAO Scheduler] Evicted ${originalLength - this.queue.length} pending "${category}" tasks.`);
    }
  }

  /**
   * 우선순위에 따라 큐를 정렬합니다. (high -> medium -> low)
   */
  private sortQueue() {
    const priorityWeight = { high: 3, medium: 2, low: 1 };
    this.queue.sort((a, b) => priorityWeight[b.priority] - priorityWeight[a.priority]);
  }

  /**
   * 큐에 대기 중인 다음 작업을 실행 가능한 경우 실행합니다.
   */
  private async processNext() {
    if (this.activeCount >= this.maxConcurrency || this.queue.length === 0) {
      return;
    }

    const task = this.queue.shift();
    if (!task) return;

    this.activeCount++;
    console.log(`[LAO Scheduler] Spawning task [ID: ${task.id}] in category "${task.category}" (Active: ${this.activeCount}/${this.maxConcurrency})`);

    let childProcess: ChildProcess | null = null;
    let timeoutTimer: NodeJS.Timeout | null = null;
    let completed = false;

    // 타임아웃 가드 설정
    if (task.timeoutMs > 0) {
      timeoutTimer = setTimeout(() => {
        if (!completed) {
          completed = true;
          console.warn(`[LAO Scheduler] Task [ID: ${task.id}] timed out after ${task.timeoutMs}ms. Sending SIGKILL to child process.`);
          if (childProcess) {
            try {
              // 좀비 프로세스 방지를 위해 강제 종료
              childProcess.kill('SIGKILL');
            } catch (err) {
              console.error(`[LAO Scheduler] Failed to kill timed out process [ID: ${task.id}]:`, err);
            }
          }
          task.reject(new Error(`Task timed out after ${task.timeoutMs}ms.`));
          this.activeCount--;
          this.processNext();
        }
      }, task.timeoutMs);
    }

    try {
      const result = await task.run({
        setProcess: (proc: ChildProcess) => {
          childProcess = proc;
        }
      });

      if (!completed) {
        completed = true;
        if (timeoutTimer) clearTimeout(timeoutTimer);
        task.resolve(result);
        this.activeCount--;
        this.processNext();
      }
    } catch (error) {
      if (!completed) {
        completed = true;
        if (timeoutTimer) clearTimeout(timeoutTimer);
        task.reject(error);
        this.activeCount--;
        this.processNext();
      }
    }
  }
}
