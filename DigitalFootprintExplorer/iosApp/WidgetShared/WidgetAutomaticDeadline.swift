/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

// [01] One result wins. A late API result cannot save after the timeout has returned the old garden.
final class WidgetAutomaticTerminal: @unchecked Sendable {
    private let lock = NSLock()
    private let deadlineUptime: TimeInterval
    private let timeout: (Bool) -> Void
    private let completion: () -> Void
    private var task: Task<Void, Never>?
    private var work: DispatchWorkItem?
    private var finished = false
    private var calculationSucceeded = false

    init(deadlineUptime: TimeInterval, timeout: @escaping (Bool) -> Void, completion: @escaping () -> Void) {
        self.deadlineUptime = deadlineUptime
        self.timeout = timeout
        self.completion = completion
    }

    func arm() {
        let item = DispatchWorkItem { self.finishTimeout() }
        lock.lock(); work = item; lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, deadlineUptime - ProcessInfo.processInfo.systemUptime), execute: item)
    }

    func setTask(_ value: Task<Void, Never>) {
        lock.lock()
        if finished { lock.unlock(); value.cancel(); return }
        task = value
        lock.unlock()
    }

    func noteCalculationSucceeded() {
        lock.lock(); defer { lock.unlock() }
        if !finished { calculationSucceeded = true }
    }

    func finishQuery(_ saveIfCurrent: () -> Void) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if ProcessInfo.processInfo.systemUptime >= deadlineUptime {
            lock.unlock()
            finishTimeout()
            return
        }
        finished = true
        let deadline = work
        work = nil
        task = nil
        lock.unlock()
        deadline?.cancel()
        // [02] The exchange checks consent again under its file lock before its short, protected save.
        saveIfCurrent()
        completion()
    }

    private func finishTimeout() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let calculated = calculationSucceeded
        let active = task
        task = nil
        work = nil
        lock.unlock()
        active?.cancel()
        timeout(calculated)
        completion()
    }
}
