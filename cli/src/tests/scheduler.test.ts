import { SpawnQueueManager } from '../scheduler';
import { ChildProcess } from 'child_process';

describe('SpawnQueueManager Unit Tests', () => {
  let scheduler: SpawnQueueManager;

  beforeEach(() => {
    // SpawnQueueManager는 싱글톤이므로 내부 상태가 이전 테스트에 의해 오염될 수 있습니다.
    // 하지만 private 필드로 queue와 activeCount가 설정되어 있으므로 테스트 케이스 진행 시 순서대로 온전히 제어합니다.
    scheduler = SpawnQueueManager.getInstance();
  });

  describe('TC-SQM-01: Concurrency Control (maxConcurrency = 2)', () => {
    it('should limit active concurrent tasks to 2 and queue the remaining tasks', async () => {
      const startTimes: { [key: string]: number } = {};
      const endTimes: { [key: string]: number } = {};
      
      const createDelayedTask = (name: string, delayMs: number) => {
        return async (taskRef: { setProcess: (proc: ChildProcess) => void }) => {
          startTimes[name] = Date.now();
          await new Promise(resolve => setTimeout(resolve, delayMs));
          endTimes[name] = Date.now();
          return name;
        };
      };

      // 3개의 작업을 순서대로 등록
      // Task A: 100ms 실행
      // Task B: 100ms 실행
      // Task C: 50ms 실행
      const promiseA = scheduler.enqueue('inference', 'medium', createDelayedTask('A', 100));
      const promiseB = scheduler.enqueue('inference', 'medium', createDelayedTask('B', 100));
      const promiseC = scheduler.enqueue('inference', 'medium', createDelayedTask('C', 50));

      const results = await Promise.all([promiseA, promiseB, promiseC]);

      expect(results).toEqual(['A', 'B', 'C']);

      // Task A와 B는 거의 동시에 시작되었어야 함
      const timeDiffAB = Math.abs(startTimes['A'] - startTimes['B']);
      expect(timeDiffAB).toBeLessThan(35); // 35ms 이내 기동

      // Task C는 A 또는 B 중 하나가 끝난 시점 이후에 시작되었어야 함
      // A와 B 중 최소 종료 시간
      const firstEnd = Math.min(endTimes['A'], endTimes['B']);
      // C의 시작 시간은 최초 종료 시간 근처 또는 그 이후여야 함
      expect(startTimes['C']).toBeGreaterThanOrEqual(firstEnd - 10); // 소량의 스케줄 오차 감안
    });
  });

  describe('TC-SQM-02: mockup category task Deduplication (Eviction)', () => {
    it('should evict pending mockup tasks when a newer mockup task is enqueued', async () => {
      // 1. Concurrency 한도를 채우기 위해 2개의 무거운 inference 작업 실행
      const blockSignal = { resolve: () => {} };
      const blockPromise = new Promise<void>(resolve => {
        blockSignal.resolve = resolve;
      });

      const createBlockingTask = () => {
        return async (taskRef: { setProcess: (proc: ChildProcess) => void }) => {
          await blockPromise;
          return 'blocked_done';
        };
      };

      const runningA = scheduler.enqueue('inference', 'medium', createBlockingTask());
      const runningB = scheduler.enqueue('inference', 'medium', createBlockingTask());

      // 2. pending 큐에 들어가게 될 mockup 작업 A 인큐
      const mockupPromiseA = scheduler.enqueue('mockup', 'medium', async () => {
        return 'mockup_A';
      });

      // 3. 즉시 새로운 mockup 작업 B 인큐
      const mockupPromiseB = scheduler.enqueue('mockup', 'medium', async () => {
        return 'mockup_B';
      });

      // mockup A는 새로운 mockup B에 의해 eviction(reject) 되어야 함
      await expect(mockupPromiseA).rejects.toThrow('Superseded by a newer task of category: mockup');

      // 4. block 해제하여 남아있는 큐 처리
      blockSignal.resolve();

      // runningA, runningB 및 mockupB가 모두 완료되어야 함
      const results = await Promise.all([runningA, runningB, mockupPromiseB]);
      expect(results).toEqual(['blocked_done', 'blocked_done', 'mockup_B']);
    });
  });

  describe('TC-SQM-03: Timeout Guard and SIGKILL handler', () => {
    it('should time out task, invoke SIGKILL on child process, and reject the promise', async () => {
      const mockKill = jest.fn();
      const mockChildProcess = {
        kill: mockKill
      } as unknown as ChildProcess;

      const runFn = async (taskRef: { setProcess: (proc: ChildProcess) => void }) => {
        taskRef.setProcess(mockChildProcess);
        // 무한정 대기하는 비동기 함수 시뮬레이션
        await new Promise(resolve => setTimeout(resolve, 500));
        return 'should_not_reach_here';
      };

      // 50ms 타임아웃 설정
      const testPromise = scheduler.enqueue('inference', 'medium', runFn, 50);

      await expect(testPromise).rejects.toThrow('Task timed out after 50ms.');
      
      // SIGKILL이 해당 프로세스에 송신되었는지 검증
      expect(mockKill).toHaveBeenCalledWith('SIGKILL');
    });
  });
});
