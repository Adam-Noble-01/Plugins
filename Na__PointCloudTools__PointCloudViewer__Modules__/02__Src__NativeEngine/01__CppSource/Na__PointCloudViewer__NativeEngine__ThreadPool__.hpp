// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - THREAD POOL
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp
// PURPOSE    : Fixed pool of workers for data-parallel frame work. Run() hands
//              every worker the same task with its index and blocks until all
//              have finished - the calling (SketchUp main) thread only waits.
//
// LIFETIME   : Created on first use, destroyed only by napc_shutdown(). Never
//              a static object: joining threads from a DLL's static destructor
//              at process exit can deadlock on the loader lock.
//
// =============================================================================

#pragma once

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

class Na__ThreadPool {
public:
    explicit Na__ThreadPool(unsigned thread_count) {
        if (thread_count == 0) thread_count = 1;
        m_workers.reserve(thread_count);
        for (unsigned index = 0; index < thread_count; ++index) {
            m_workers.emplace_back([this, index] { WorkerLoop(index); });
        }
    }

    ~Na__ThreadPool() {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_stopping = true;
            ++m_generation;
        }
        m_start.notify_all();
        for (std::thread& worker : m_workers) worker.join();
    }

    Na__ThreadPool(const Na__ThreadPool&) = delete;
    Na__ThreadPool& operator=(const Na__ThreadPool&) = delete;

    unsigned Size() const { return static_cast<unsigned>(m_workers.size()); }

    // task(worker_index, worker_count)
    void Run(const std::function<void(unsigned, unsigned)>& task) {
        std::unique_lock<std::mutex> lock(m_mutex);
        m_task    = &task;
        m_pending = Size();
        ++m_generation;
        m_start.notify_all();
        m_done.wait(lock, [this] { return m_pending == 0; });
        m_task = nullptr;
    }

private:
    void WorkerLoop(unsigned index) {
        uint64_t seen = 0;
        for (;;) {
            const std::function<void(unsigned, unsigned)>* task = nullptr;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                m_start.wait(lock, [this, seen] { return m_generation != seen; });
                seen = m_generation;
                if (m_stopping) return;
                task = m_task;
            }
            if (task) (*task)(index, Size());
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (--m_pending == 0) m_done.notify_one();
            }
        }
    }

    std::vector<std::thread> m_workers;
    std::mutex m_mutex;
    std::condition_variable m_start;
    std::condition_variable m_done;
    const std::function<void(unsigned, unsigned)>* m_task = nullptr;
    unsigned m_pending = 0;
    uint64_t m_generation = 0;
    bool m_stopping = false;
};
