/** Keep coloring and super-resolution native allocations from overlapping during mode switches. */
export class ReaderComicComputeQueue {
  private static tail: Promise<void> = Promise.resolve();

  static run<T>(work: () => Promise<T>): Promise<T> {
    const task = ReaderComicComputeQueue.tail.then(work);
    ReaderComicComputeQueue.tail = task.then((): void => {}, (): void => {});
    return task;
  }
}
