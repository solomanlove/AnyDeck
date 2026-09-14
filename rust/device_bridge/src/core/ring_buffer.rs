//! 高性能定长环形日志队列：维护固定容量 (默认 20,000 条) 日志槽位，
//! 支持基于 Level、PID、Tag 与关键字的极速虚拟视口过滤。

use std::sync::RwLock;
use serde::{Deserialize, Serialize};

/// 原生单条日志条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    /// 全局自增序号
    pub id: u64,
    /// 格式化时间戳字符串 (例如 "12-31 23:59:59.999")
    pub timestamp: String,
    /// 日志级别 (2=V, 3=D, 4=I, 5=W, 6=E, 7=F)
    pub level: u8,
    /// 进程 ID
    pub pid: u32,
    /// 线程 ID
    pub tid: u32,
    /// 日志 Tag
    pub tag: String,
    /// 日志主体内容
    pub message: String,
}

/// 定长高性能环形日志缓冲区
pub struct LogRingBuffer {
    capacity: usize,
    buffer: RwLock<Vec<LogEntry>>,
    next_id: RwLock<u64>,
}

impl LogRingBuffer {
    /// 默认环形缓冲容量 (20,000 行，兼顾内存占用与回溯深度)
    pub const DEFAULT_CAPACITY: usize = 20_000;

    /// 创建指定容量的环形缓冲区实例
    pub fn new(capacity: usize) -> Self {
        let cap = if capacity == 0 {
            Self::DEFAULT_CAPACITY
        } else {
            capacity
        };
        Self {
            capacity: cap,
            buffer: RwLock::new(Vec::with_capacity(cap.min(Self::DEFAULT_CAPACITY))),
            next_id: RwLock::new(1),
        }
    }

    /// 向环形缓冲区追加单条日志，若已满则丢弃最久远的一条
    pub fn push(&self, mut entry: LogEntry) {
        let mut id_guard = self.next_id.write().unwrap();
        entry.id = *id_guard;
        *id_guard = id_guard.wrapping_add(1);
        drop(id_guard);

        let mut buf = self.buffer.write().unwrap();
        if buf.len() >= self.capacity {
            buf.remove(0);
        }
        buf.push(entry);
    }

    /// 虚拟视口过滤查询：倒序（最新日志优先），支持 Level、PID、Tag、关键字与分页
    pub fn query(
        &self,
        min_level: u8,
        pid: Option<u32>,
        tag: Option<&str>,
        keyword: Option<&str>,
        offset: usize,
        limit: usize,
    ) -> Vec<LogEntry> {
        let buf = self.buffer.read().unwrap();
        buf.iter()
            .rev()
            .filter(|e| {
                if e.level < min_level {
                    return false;
                }
                if let Some(target_pid) = pid {
                    if e.pid != target_pid {
                        return false;
                    }
                }
                if let Some(target_tag) = tag {
                    if !e.tag.contains(target_tag) {
                        return false;
                    }
                }
                if let Some(kw) = keyword {
                    if !e.message.contains(kw) && !e.tag.contains(kw) {
                        return false;
                    }
                }
                true
            })
            .skip(offset)
            .take(limit)
            .cloned()
            .collect()
    }

    /// 获取当前缓冲区中已存日志行数
    pub fn len(&self) -> usize {
        self.buffer.read().unwrap().len()
    }

    /// 判断缓冲区是否为空
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// 清空所有日志数据
    pub fn clear(&self) {
        self.buffer.write().unwrap().clear();
    }
}
