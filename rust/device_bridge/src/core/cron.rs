//! 轻量级 Cron 定时调度器引擎
//! 支持标准 5 字段 Cron 表达式（分 时 日 月 周），用于夜间自动巡检、定时性能压测与报表自动化。
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use serde::{Deserialize, Serialize};

/// 5 字段 Cron 表达式规则
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CronExpression {
    pub raw: String,
    pub minutes: Vec<u8>,
    pub hours: Vec<u8>,
    pub days: Vec<u8>,
    pub months: Vec<u8>,
    pub weekdays: Vec<u8>,
}

impl CronExpression {
    /// 解析标准 5 字段 Cron 字符串 (如 `*/5 * * * *`)
    pub fn parse(expr: &str) -> Result<Self, String> {
        let parts: Vec<&str> = expr.split_whitespace().collect();
        if parts.len() != 5 {
            return Err(format!("Cron expression must have exactly 5 fields, got {}", parts.len()));
        }

        let minutes = parse_field(parts[0], 0, 59)?;
        let hours = parse_field(parts[1], 0, 23)?;
        let days = parse_field(parts[2], 1, 31)?;
        let months = parse_field(parts[3], 1, 12)?;
        let weekdays = parse_field(parts[4], 0, 6)?;

        Ok(Self {
            raw: expr.to_string(),
            minutes,
            hours,
            days,
            months,
            weekdays,
        })
    }

    /// 判定给定的时间分量是否满足此 Cron 表达式
    pub fn matches(&self, minute: u8, hour: u8, day: u8, month: u8, weekday: u8) -> bool {
        self.minutes.contains(&minute)
            && self.hours.contains(&hour)
            && self.days.contains(&day)
            && self.months.contains(&month)
            && self.weekdays.contains(&weekday)
    }
}

/// 解析单个字段表达式 (如 `*`, `*/10`, `1,2,5`, `10-15`)
fn parse_field(field: &str, min: u8, max: u8) -> Result<Vec<u8>, String> {
    let mut values = Vec::new();

    for part in field.split(',') {
        let trimmed = part.trim();
        if trimmed == "*" {
            values.extend(min..=max);
        } else if let Some(step_str) = trimmed.strip_prefix("*/") {
            let step: u8 = step_str.parse().map_err(|e| format!("Invalid step '{step_str}': {e}"))?;
            if step == 0 {
                return Err("Step cannot be 0".into());
            }
            let mut curr = min;
            while curr <= max {
                values.push(curr);
                curr = match curr.checked_add(step) {
                    Some(next) => next,
                    None => break,
                };
            }
        } else if trimmed.contains('-') {
            let range_parts: Vec<&str> = trimmed.split('-').collect();
            if range_parts.len() != 2 {
                return Err(format!("Invalid range syntax '{trimmed}'"));
            }
            let start: u8 = range_parts[0].parse().map_err(|e| format!("Invalid range start: {e}"))?;
            let end: u8 = range_parts[1].parse().map_err(|e| format!("Invalid range end: {e}"))?;
            if start > end || start < min || end > max {
                return Err(format!("Range {start}-{end} out of bounds ({min}-{max})"));
            }
            values.extend(start..=end);
        } else {
            let single: u8 = trimmed.parse().map_err(|e| format!("Invalid number '{trimmed}': {e}"))?;
            if single < min || single > max {
                return Err(format!("Value {single} out of bounds ({min}-{max})"));
            }
            values.push(single);
        }
    }

    values.sort_unstable();
    values.dedup();
    Ok(values)
}

/// 定时任务描述
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CronJob {
    pub id: String,
    pub name: String,
    pub expression: String,
    pub enabled: bool,
}

/// 全局 Cron 调度管理器
pub struct CronScheduler {
    jobs: Mutex<HashMap<String, (CronJob, CronExpression)>>,
}

impl CronScheduler {
    pub fn global() -> &'static Self {
        static INSTANCE: OnceLock<CronScheduler> = OnceLock::new();
        INSTANCE.get_or_init(|| CronScheduler {
            jobs: Mutex::new(HashMap::new()),
        })
    }

    /// 注册或更新一个定时调度任务
    pub fn add_job(&self, id: impl Into<String>, name: impl Into<String>, expression: &str) -> Result<(), String> {
        let cron_expr = CronExpression::parse(expression)?;
        let id_str = id.into();
        let job = CronJob {
            id: id_str.clone(),
            name: name.into(),
            expression: expression.to_string(),
            enabled: true,
        };

        let mut lock = self.jobs.lock().map_err(|_| "Cron lock poisoned".to_string())?;
        lock.insert(id_str, (job, cron_expr));
        Ok(())
    }

    /// 移除定时任务
    pub fn remove_job(&self, id: &str) -> bool {
        if let Ok(mut lock) = self.jobs.lock() {
            lock.remove(id).is_some()
        } else {
            false
        }
    }

    /// 列出所有定时任务清单 (JSON 格式)
    pub fn list_jobs_json(&self) -> String {
        if let Ok(lock) = self.jobs.lock() {
            let list: Vec<&CronJob> = lock.values().map(|(j, _)| j).collect();
            serde_json::to_string(&list).unwrap_or_else(|_| "[]".into())
        } else {
            "[]".into()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cron_expression_parsing() {
        let expr = CronExpression::parse("*/15 2 1-5 * 1,3,5").unwrap();
        assert_eq!(expr.minutes, vec![0, 15, 30, 45]);
        assert_eq!(expr.hours, vec![2]);
        assert_eq!(expr.days, vec![1, 2, 3, 4, 5]);
        assert_eq!(expr.months, (1..=12).collect::<Vec<u8>>());
        assert_eq!(expr.weekdays, vec![1, 3, 5]);

        // 测试匹配
        assert!(expr.matches(15, 2, 3, 6, 1));
        assert!(!expr.matches(10, 2, 3, 6, 1));
        assert!(!expr.matches(15, 3, 3, 6, 1));
    }

    #[test]
    fn test_cron_scheduler() {
        let scheduler = CronScheduler::global();
        let _ = scheduler.add_job("job_1", "Nightly Inspection", "0 3 * * *");
        let list_json = scheduler.list_jobs_json();
        assert!(list_json.contains("Nightly Inspection"));
        assert!(scheduler.remove_job("job_1"));
    }
}
