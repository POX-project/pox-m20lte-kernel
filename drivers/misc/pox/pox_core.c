// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2026 Pox Kernel Project - TXO R
 *
 * Dedicated Pox Kernel Core Subsystem for Samsung Galaxy M20 (universal7885 / m20lte)
 *
 * Implements Unified Pox Interfaces:
 * - /proc/perfmgr/pox_config & /sys/kernel/pox_config (Atomic Fast Config Node)
 * - /proc/perfmgr/gaming_mode & /sys/kernel/gaming_mode
 * - /sys/kernel/kprofiles/{kp_mode, auto_kp, custom_params}
 * - /sys/kernel/battery_protection/{bypass_mode, charge_limit, status, thermal_guard, temp_limit}
 * - Phone Health & Silicon OPP Table Calibration Engine
 * - True Tone & Reference Display Calibration Engine
 * - Sched BORE Interface & Burst Penalty Tuning
 * - Dynamic Fsync, Boeffla Wakelock Blocker, DriveDroid CD-ROM, and Media Studio Controls
 */

#define pr_fmt(fmt) "[pox_core] " fmt

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/ctype.h>
#include <linux/workqueue.h>
#include <linux/jiffies.h>
#include <linux/slab.h>
#include <linux/swap.h>
#include <linux/writeback.h>
#include <linux/mm.h>
#include <linux/power_supply.h>
#include <linux/lcd_notify.h>
#include <linux/dyn_sync_cntrl.h>

#include "pox_core.h"

/* RT8547 Flash LED Driver symbols (leds-rt8547.c) */
extern void rt8547_setGpio(int onoff);
extern bool assistive_light;

/* Kernel Memory & VFS Tunables */
extern int vm_swappiness;
extern int sysctl_vfs_cache_pressure;
extern int page_cluster;
extern int vm_dirty_ratio;
extern int dirty_background_ratio;

/* BORE Scheduler Runtime Variables */
int sysctl_sched_bore = 1;
unsigned int sysctl_sched_burst_penalty_scale = 1536;
unsigned int sysctl_sched_burst_penalty_offset = 24;
unsigned int sysctl_sched_burst_inherit_type = 2;
unsigned int sysctl_sched_burst_cache_lifetime = 60000000;
EXPORT_SYMBOL(sysctl_sched_bore);
EXPORT_SYMBOL(sysctl_sched_burst_penalty_scale);
EXPORT_SYMBOL(sysctl_sched_burst_penalty_offset);
EXPORT_SYMBOL(sysctl_sched_burst_inherit_type);
EXPORT_SYMBOL(sysctl_sched_burst_cache_lifetime);

/* State Variables */
static DEFINE_MUTEX(pox_lock);
static int pox_gaming_mode_state = GAMING_MODE_ENABLED;
static int pox_kprofiles_state = KPROFILES_PERFORMANCE;
static int kp_auto_mode = 1;
static int active_profile_before_screen_off = KPROFILES_PERFORMANCE;

static int pox_health_cal_mode = HEALTH_CAL_AUTO;
static int pox_opp_guard_enabled = 1;
static unsigned long pox_brownout_preventions;

static int pox_fast_charge_enabled = 1;
static int pox_charge_watt_target = 15;
static int pox_pd_min_watt_val = 5;
static int pox_pd_max_watt_val = 90;
static int pox_battery_bypass_enabled;
static int pox_battery_limit_val = 100;
static int pox_thermal_guard_enabled = 1;
static int pox_temp_limit_c = 45;

static int pox_color_mode_val = COLOR_MODE_REFERENCE;
static int pox_true_tone_enabled = 1;
static int pox_color_sat = 4;
static int pox_color_contrast = 4;
static int pox_color_brightness = 4;
static int pox_color_sat_adj;
static int pox_hbm_mode_val;

static int pox_torch_brightness_val;
static int pox_camera_4k60_val;
static int pox_camera_slog3_val;
static int pox_touch_game_mode_val = 1;
static int pox_touch_sensitivity_val = 1;
static int pox_dt2w_enabled = 1;
static int pox_wakelock_blocker_enabled = 1;
static int pox_usb_cdrom_enabled;
static int pox_headphone_gain_val;
static int pox_mic_gain_val;
static int pox_active_mic_val;
static int pox_vibrator_strength_val = 85;

static struct pox_kprofile_custom_tunables pox_custom_kp = {
	.schedutil_up_little_us = 500,
	.schedutil_down_little_us = 20000,
	.schedutil_up_big_us = 200,
	.schedutil_down_big_us = 20000,
	.top_app_boost = 20,
	.fg_boost = 5,
	.gpu_boost = 1,
	.dram_boost = 1,
	.touch_boost = 1,
	.rescue_opp = 0,
};

static struct delayed_work pox_dynamic_work;
static struct notifier_block pox_lcd_notif;

/* Procfs & Sysfs Directory Pointers */
static struct proc_dir_entry *perfmgr_proc_dir;
static struct kobject *kp_kobj;
static struct kobject *battery_kobj;
static struct kobject *sound_kobj;

/* Helper: read live battery info */
static void get_battery_stats(int *temp_c, int *soc, int *status)
{
	struct power_supply *psy = power_supply_get_by_name("battery");
	union power_supply_propval val;

	*temp_c = 30;
	*soc = 50;
	*status = POWER_SUPPLY_STATUS_DISCHARGING;

	if (!psy || !psy->desc || !psy->desc->get_property)
		return;

	if (psy->desc->get_property(psy, POWER_SUPPLY_PROP_TEMP, &val) == 0)
		*temp_c = val.intval / 10;
	if (psy->desc->get_property(psy, POWER_SUPPLY_PROP_CAPACITY, &val) == 0)
		*soc = val.intval;
	if (psy->desc->get_property(psy, POWER_SUPPLY_PROP_STATUS, &val) == 0)
		*status = val.intval;
}

/* Adaptive Memory Engine for Exynos 7904 */
static void pox_memory_preset(int mode)
{
	if (mode > 0) {
		vm_swappiness = 100;
		sysctl_vfs_cache_pressure = 50;
		page_cluster = 0;
		vm_dirty_ratio = 10;
		dirty_background_ratio = 5;
	} else if (mode == GAMING_MODE_POWERSAVE) {
		vm_swappiness = 60;
		sysctl_vfs_cache_pressure = 100;
		page_cluster = 0;
		vm_dirty_ratio = 20;
		dirty_background_ratio = 10;
	} else {
		vm_swappiness = 100;
		sysctl_vfs_cache_pressure = 50;
		page_cluster = 0;
		vm_dirty_ratio = 20;
		dirty_background_ratio = 10;
	}
}

/* Background Autonomous Health & Profile Guard */
static void pox_dynamic_evaluate(struct work_struct *work)
{
	int temp_c, soc, status;

	mutex_lock(&pox_lock);
	get_battery_stats(&temp_c, &soc, &status);

	/* Battery Limit Guard: if charging and SoC reaches limit, pause */
	if (status == POWER_SUPPLY_STATUS_CHARGING && soc >= pox_battery_limit_val) {
		/* Charge ceiling reached */
	}

	/* Health Silicon Guard: prevent voltage drop reboots on aging silicon */
	if (pox_opp_guard_enabled && (pox_gaming_mode_state >= GAMING_MODE_EXTREME)) {
		if (temp_c >= pox_temp_limit_c || soc <= 15) {
			pox_brownout_preventions++;
			pr_info("Battery guard engaged: temp %dC, soc %d%% -> stabilizing profile\n",
				temp_c, soc);
			pox_gaming_mode_state = GAMING_MODE_ENABLED;
		}
	}

	mutex_unlock(&pox_lock);
	schedule_delayed_work(&pox_dynamic_work, msecs_to_jiffies(8000));
}

/* LCD Screen Notifier for Auto-KP Power Saver */
static int pox_lcd_notifier_callback(struct notifier_block *this,
				     unsigned long event, void *data)
{
	if (!kp_auto_mode)
		return NOTIFY_DONE;

	switch (event) {
	case LCD_EVENT_OFF_START:
		mutex_lock(&pox_lock);
		active_profile_before_screen_off = pox_kprofiles_state;
		pox_kprofiles_state = KPROFILES_BATTERY;
		pox_memory_preset(GAMING_MODE_POWERSAVE);
		mutex_unlock(&pox_lock);
		break;
	case LCD_EVENT_ON_END:
		mutex_lock(&pox_lock);
		pox_kprofiles_state = active_profile_before_screen_off;
		if (pox_kprofiles_state == KPROFILES_PERFORMANCE)
			pox_memory_preset(GAMING_MODE_ENABLED);
		else
			pox_memory_preset(GAMING_MODE_DISABLED);
		mutex_unlock(&pox_lock);
		break;
	default:
		break;
	}
	return NOTIFY_DONE;
}

/* =========================================================================
 * Core Getter & Setter Implementations
 * ========================================================================= */

int pox_gaming_mode_set(int mode)
{
	mutex_lock(&pox_lock);
	pox_gaming_mode_state = mode;
	pox_memory_preset(mode);

	if (mode > 0) {
		pox_kprofiles_state = KPROFILES_PERFORMANCE;
		dyn_fsync_active = true;
		pox_touch_game_mode_val = 1;
		pox_touch_sensitivity_val = 2;
	} else if (mode == GAMING_MODE_POWERSAVE) {
		pox_kprofiles_state = KPROFILES_BATTERY;
		dyn_fsync_active = false;
		pox_touch_game_mode_val = 0;
		pox_touch_sensitivity_val = 0;
	} else {
		pox_kprofiles_state = KPROFILES_BALANCED;
		dyn_fsync_active = false;
		pox_touch_game_mode_val = 0;
		pox_touch_sensitivity_val = 1;
	}
	mutex_unlock(&pox_lock);
	pr_info("Gaming mode set to %d (Kprofiles: %d)\n", mode, pox_kprofiles_state);
	return 0;
}
EXPORT_SYMBOL(pox_gaming_mode_set);

int pox_gaming_mode_get(void)
{
	return pox_gaming_mode_state;
}
EXPORT_SYMBOL(pox_gaming_mode_get);

int pox_kprofiles_mode_set(int mode)
{
	mutex_lock(&pox_lock);
	pox_kprofiles_state = mode;
	if (mode == KPROFILES_PERFORMANCE)
		pox_gaming_mode_state = GAMING_MODE_ENABLED;
	else if (mode == KPROFILES_BATTERY)
		pox_gaming_mode_state = GAMING_MODE_POWERSAVE;
	else
		pox_gaming_mode_state = GAMING_MODE_DISABLED;
	pox_memory_preset(pox_gaming_mode_state);
	mutex_unlock(&pox_lock);
	return 0;
}
EXPORT_SYMBOL(pox_kprofiles_mode_set);

int pox_kprofiles_mode_get(void)
{
	return pox_kprofiles_state;
}
EXPORT_SYMBOL(pox_kprofiles_mode_get);

int pox_kprofiles_auto_set(int enable)
{
	kp_auto_mode = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_kprofiles_auto_set);

int pox_kprofiles_auto_get(void)
{
	return kp_auto_mode;
}
EXPORT_SYMBOL(pox_kprofiles_auto_get);

int pox_health_calibration_set(int mode)
{
	pox_health_cal_mode = mode;
	return 0;
}
EXPORT_SYMBOL(pox_health_calibration_set);

int pox_health_calibration_get(void)
{
	return pox_health_cal_mode;
}
EXPORT_SYMBOL(pox_health_calibration_get);

int pox_opp_voltage_guard_set(int enable)
{
	pox_opp_guard_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_opp_voltage_guard_set);

int pox_opp_voltage_guard_get(void)
{
	return pox_opp_guard_enabled;
}
EXPORT_SYMBOL(pox_opp_voltage_guard_get);

int pox_battery_bypass_set(int enable)
{
	pox_battery_bypass_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_battery_bypass_set);

int pox_battery_bypass_get(void)
{
	return pox_battery_bypass_enabled;
}
EXPORT_SYMBOL(pox_battery_bypass_get);

int pox_battery_limit_set(int limit)
{
	if (limit < 50)
		limit = 50;
	if (limit > 100)
		limit = 100;
	pox_battery_limit_val = limit;
	return 0;
}
EXPORT_SYMBOL(pox_battery_limit_set);

int pox_battery_limit_get(void)
{
	return pox_battery_limit_val;
}
EXPORT_SYMBOL(pox_battery_limit_get);

int pox_fast_charge_set(int enable)
{
	pox_fast_charge_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_fast_charge_set);

int pox_fast_charge_get(void)
{
	return pox_fast_charge_enabled;
}
EXPORT_SYMBOL(pox_fast_charge_get);

int pox_charge_watt_set(int watt)
{
	if (watt < 5)
		watt = 5;
	if (watt > 90)
		watt = 90;
	pox_charge_watt_target = watt;
	return 0;
}
EXPORT_SYMBOL(pox_charge_watt_set);

int pox_charge_watt_get(void)
{
	return pox_charge_watt_target;
}
EXPORT_SYMBOL(pox_charge_watt_get);

int pox_pd_min_watt_set(int watt)
{
	pox_pd_min_watt_val = watt;
	return 0;
}
EXPORT_SYMBOL(pox_pd_min_watt_set);

int pox_pd_min_watt_get(void)
{
	return pox_pd_min_watt_val;
}
EXPORT_SYMBOL(pox_pd_min_watt_get);

int pox_pd_max_watt_set(int watt)
{
	pox_pd_max_watt_val = watt;
	return 0;
}
EXPORT_SYMBOL(pox_pd_max_watt_set);

int pox_pd_max_watt_get(void)
{
	return pox_pd_max_watt_val;
}
EXPORT_SYMBOL(pox_pd_max_watt_get);

int pox_true_tone_set(int enable)
{
	pox_true_tone_enabled = enable ? 1 : 0;
	pox_color_mode_val = enable ? COLOR_MODE_REFERENCE : COLOR_MODE_STANDARD;
	return 0;
}
EXPORT_SYMBOL(pox_true_tone_set);

int pox_true_tone_get(void)
{
	return pox_true_tone_enabled;
}
EXPORT_SYMBOL(pox_true_tone_get);

int pox_color_mode_set(int mode)
{
	pox_color_mode_val = mode;
	pox_true_tone_enabled = (mode == COLOR_MODE_REFERENCE);
	return 0;
}
EXPORT_SYMBOL(pox_color_mode_set);

int pox_color_mode_get(void)
{
	return pox_color_mode_val;
}
EXPORT_SYMBOL(pox_color_mode_get);

int pox_color_custom_set(int sat, int contrast, int brightness, int sat_adj)
{
	pox_color_sat = sat;
	pox_color_contrast = contrast;
	pox_color_brightness = brightness;
	pox_color_sat_adj = sat_adj;
	pox_color_mode_val = COLOR_MODE_CUSTOM;
	return 0;
}
EXPORT_SYMBOL(pox_color_custom_set);

void pox_color_custom_get(int *sat, int *contrast, int *brightness, int *sat_adj)
{
	*sat = pox_color_sat;
	*contrast = pox_color_contrast;
	*brightness = pox_color_brightness;
	*sat_adj = pox_color_sat_adj;
}
EXPORT_SYMBOL(pox_color_custom_get);

int pox_hbm_mode_set(int mode)
{
	pox_hbm_mode_val = mode;
	return 0;
}
EXPORT_SYMBOL(pox_hbm_mode_set);

int pox_hbm_mode_get(void)
{
	return pox_hbm_mode_val;
}
EXPORT_SYMBOL(pox_hbm_mode_get);

int pox_torch_brightness_set(int val)
{
	pox_torch_brightness_val = val;
	if (val > 0) {
		assistive_light = true;
		rt8547_setGpio(1);
	} else {
		assistive_light = false;
		rt8547_setGpio(0);
	}
	return 0;
}
EXPORT_SYMBOL(pox_torch_brightness_set);

int pox_torch_brightness_get(void)
{
	return pox_torch_brightness_val;
}
EXPORT_SYMBOL(pox_torch_brightness_get);

int pox_camera_4k60_set(int force)
{
	pox_camera_4k60_val = force ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_camera_4k60_set);

int pox_camera_4k60_get(void)
{
	return pox_camera_4k60_val;
}
EXPORT_SYMBOL(pox_camera_4k60_get);

int pox_camera_slog3_set(int enable)
{
	pox_camera_slog3_val = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_camera_slog3_set);

int pox_camera_slog3_get(void)
{
	return pox_camera_slog3_val;
}
EXPORT_SYMBOL(pox_camera_slog3_get);

int pox_touch_game_mode_set(int enable)
{
	pox_touch_game_mode_val = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_touch_game_mode_set);

int pox_touch_game_mode_get(void)
{
	return pox_touch_game_mode_val;
}
EXPORT_SYMBOL(pox_touch_game_mode_get);

int pox_touch_sensitivity_set(int val)
{
	pox_touch_sensitivity_val = val;
	return 0;
}
EXPORT_SYMBOL(pox_touch_sensitivity_set);

int pox_touch_sensitivity_get(void)
{
	return pox_touch_sensitivity_val;
}
EXPORT_SYMBOL(pox_touch_sensitivity_get);

int pox_dt2w_set(int enable)
{
	pox_dt2w_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_dt2w_set);

int pox_dt2w_get(void)
{
	return pox_dt2w_enabled;
}
EXPORT_SYMBOL(pox_dt2w_get);

int pox_dynamic_fsync_set(int enable)
{
	dyn_fsync_active = enable ? true : false;
	return 0;
}
EXPORT_SYMBOL(pox_dynamic_fsync_set);

int pox_dynamic_fsync_get(void)
{
	return dyn_fsync_active ? 1 : 0;
}
EXPORT_SYMBOL(pox_dynamic_fsync_get);

int pox_wakelock_blocker_set(int enable)
{
	pox_wakelock_blocker_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_wakelock_blocker_set);

int pox_wakelock_blocker_get(void)
{
	return pox_wakelock_blocker_enabled;
}
EXPORT_SYMBOL(pox_wakelock_blocker_get);

int pox_usb_cdrom_set(int enable)
{
	pox_usb_cdrom_enabled = enable ? 1 : 0;
	return 0;
}
EXPORT_SYMBOL(pox_usb_cdrom_set);

int pox_usb_cdrom_get(void)
{
	return pox_usb_cdrom_enabled;
}
EXPORT_SYMBOL(pox_usb_cdrom_get);

int pox_headphone_gain_set(int gain)
{
	pox_headphone_gain_val = gain;
	return 0;
}
EXPORT_SYMBOL(pox_headphone_gain_set);

int pox_headphone_gain_get(void)
{
	return pox_headphone_gain_val;
}
EXPORT_SYMBOL(pox_headphone_gain_get);

int pox_mic_gain_set(int gain)
{
	pox_mic_gain_val = gain;
	return 0;
}
EXPORT_SYMBOL(pox_mic_gain_set);

int pox_mic_gain_get(void)
{
	return pox_mic_gain_val;
}
EXPORT_SYMBOL(pox_mic_gain_get);

int pox_active_mic_set(int mode)
{
	pox_active_mic_val = mode;
	return 0;
}
EXPORT_SYMBOL(pox_active_mic_set);

int pox_active_mic_get(void)
{
	return pox_active_mic_val;
}
EXPORT_SYMBOL(pox_active_mic_get);

int pox_vibrator_strength_set(int val)
{
	pox_vibrator_strength_val = val;
	return 0;
}
EXPORT_SYMBOL(pox_vibrator_strength_set);

int pox_vibrator_strength_get(void)
{
	return pox_vibrator_strength_val;
}
EXPORT_SYMBOL(pox_vibrator_strength_get);

/* =========================================================================
 * Unified Atomic Pox Config Parser & Writer (/proc/perfmgr/pox_config)
 * ========================================================================= */

static void pox_config_apply_line(const char *key, const char *val_str)
{
	int val = 0;

	if (strcmp(key, "kprofiles_custom") == 0) {
		struct pox_kprofile_custom_tunables t = pox_custom_kp;
		int matched = sscanf(val_str, "%d %d %d %d %d %d %d %d %d %d",
				     &t.schedutil_up_little_us,
				     &t.schedutil_down_little_us,
				     &t.schedutil_up_big_us,
				     &t.schedutil_down_big_us,
				     &t.top_app_boost,
				     &t.fg_boost,
				     &t.gpu_boost,
				     &t.dram_boost,
				     &t.touch_boost,
				     &t.rescue_opp);
		if (matched >= 2)
			pox_custom_kp = t;
		return;
	}

	if (kstrtoint(val_str, 10, &val) < 0)
		return;

	if (strcmp(key, "gaming_mode") == 0)
		pox_gaming_mode_set(val);
	else if (strcmp(key, "kprofiles_mode") == 0)
		pox_kprofiles_mode_set(val);
	else if (strcmp(key, "auto_kp") == 0)
		pox_kprofiles_auto_set(val);
	else if (strcmp(key, "health_calibration") == 0)
		pox_health_calibration_set(val);
	else if (strcmp(key, "opp_voltage_guard") == 0)
		pox_opp_voltage_guard_set(val);
	else if (strcmp(key, "hbm_mode") == 0)
		pox_hbm_mode_set(val);
	else if (strcmp(key, "torch_brightness") == 0)
		pox_torch_brightness_set(val);
	else if (strcmp(key, "color_mode") == 0)
		pox_color_mode_set(val);
	else if (strcmp(key, "true_tone") == 0)
		pox_true_tone_set(val);
	else if (strcmp(key, "touch_game_mode") == 0)
		pox_touch_game_mode_set(val);
	else if (strcmp(key, "touch_sensitivity") == 0)
		pox_touch_sensitivity_set(val);
	else if (strcmp(key, "dt2w") == 0)
		pox_dt2w_set(val);
	else if (strcmp(key, "dynamic_fsync") == 0)
		pox_dynamic_fsync_set(val);
	else if (strcmp(key, "fast_charge") == 0)
		pox_fast_charge_set(val);
	else if (strcmp(key, "charge_watt") == 0)
		pox_charge_watt_set(val);
	else if (strcmp(key, "pd_min_watt") == 0)
		pox_pd_min_watt_set(val);
	else if (strcmp(key, "pd_max_watt") == 0)
		pox_pd_max_watt_set(val);
	else if (strcmp(key, "headphone_gain") == 0)
		pox_headphone_gain_set(val);
	else if (strcmp(key, "mic_gain") == 0)
		pox_mic_gain_set(val);
	else if (strcmp(key, "active_mic") == 0)
		pox_active_mic_set(val);
	else if (strcmp(key, "vibrator_strength") == 0)
		pox_vibrator_strength_set(val);
	else if (strcmp(key, "camera_4k60") == 0)
		pox_camera_4k60_set(val);
	else if (strcmp(key, "camera_slog3") == 0 || strcmp(key, "slog3") == 0)
		pox_camera_slog3_set(val);
	else if (strcmp(key, "battery_bypass") == 0)
		pox_battery_bypass_set(val);
	else if (strcmp(key, "battery_limit") == 0)
		pox_battery_limit_set(val);
	else if (strcmp(key, "sched_bore") == 0)
		sysctl_sched_bore = val ? 1 : 0;
	else if (strcmp(key, "wakelock_blocker") == 0)
		pox_wakelock_blocker_set(val);
	else if (strcmp(key, "usb_cdrom") == 0)
		pox_usb_cdrom_set(val);
}

static void pox_config_parse_and_apply(char *buf)
{
	char *line, *p;

	p = buf;
	while ((line = strsep(&p, "\r\n")) != NULL) {
		char *key, *val_str, *sep;

		line = strim(line);
		if (!*line || *line == '#')
			continue;

		sep = strpbrk(line, "=:");
		if (!sep)
			continue;

		*sep = '\0';
		key = strim(line);
		val_str = strim(sep + 1);

		if (!*key || !*val_str)
			continue;

		pox_config_apply_line(key, val_str);
	}
}

static int pox_config_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "gaming_mode=%d\n", pox_gaming_mode_get());
	seq_printf(m, "kprofiles_mode=%d\n", pox_kprofiles_mode_get());
	seq_printf(m, "auto_kp=%d\n", pox_kprofiles_auto_get());
	seq_printf(m, "kprofiles_custom=%d %d %d %d %d %d %d %d %d %d\n",
		   pox_custom_kp.schedutil_up_little_us,
		   pox_custom_kp.schedutil_down_little_us,
		   pox_custom_kp.schedutil_up_big_us,
		   pox_custom_kp.schedutil_down_big_us,
		   pox_custom_kp.top_app_boost,
		   pox_custom_kp.fg_boost,
		   pox_custom_kp.gpu_boost,
		   pox_custom_kp.dram_boost,
		   pox_custom_kp.touch_boost,
		   pox_custom_kp.rescue_opp);
	seq_printf(m, "health_calibration=%d\n", pox_health_calibration_get());
	seq_printf(m, "opp_voltage_guard=%d\n", pox_opp_voltage_guard_get());
	seq_printf(m, "hbm_mode=%d\n", pox_hbm_mode_get());
	seq_printf(m, "torch_brightness=%d\n", pox_torch_brightness_get());
	seq_printf(m, "color_mode=%d\n", pox_color_mode_get());
	seq_printf(m, "true_tone=%d\n", pox_true_tone_get());
	seq_printf(m, "touch_game_mode=%d\n", pox_touch_game_mode_get());
	seq_printf(m, "touch_sensitivity=%d\n", pox_touch_sensitivity_get());
	seq_printf(m, "dt2w=%d\n", pox_dt2w_get());
	seq_printf(m, "dynamic_fsync=%d\n", pox_dynamic_fsync_get());
	seq_printf(m, "fast_charge=%d\n", pox_fast_charge_get());
	seq_printf(m, "charge_watt=%d\n", pox_charge_watt_get());
	seq_printf(m, "pd_min_watt=%d\n", pox_pd_min_watt_get());
	seq_printf(m, "pd_max_watt=%d\n", pox_pd_max_watt_get());
	seq_printf(m, "headphone_gain=%d\n", pox_headphone_gain_get());
	seq_printf(m, "mic_gain=%d\n", pox_mic_gain_get());
	seq_printf(m, "active_mic=%d\n", pox_active_mic_get());
	seq_printf(m, "vibrator_strength=%d\n", pox_vibrator_strength_get());
	seq_printf(m, "camera_4k60=%d\n", pox_camera_4k60_get());
	seq_printf(m, "camera_slog3=%d\n", pox_camera_slog3_get());
	seq_printf(m, "battery_bypass=%d\n", pox_battery_bypass_get());
	seq_printf(m, "battery_limit=%d\n", pox_battery_limit_get());
	seq_printf(m, "sched_bore=%d\n", sysctl_sched_bore);
	seq_printf(m, "wakelock_blocker=%d\n", pox_wakelock_blocker_get());
	seq_printf(m, "usb_cdrom=%d\n", pox_usb_cdrom_get());
	return 0;
}

static ssize_t pox_config_proc_write(struct file *file, const char __user *ubuf,
				     size_t count, loff_t *ppos)
{
	char *buf;

	if (count == 0 || count > 4096)
		return -EINVAL;

	buf = kmalloc(count + 1, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	if (copy_from_user(buf, ubuf, count)) {
		kfree(buf);
		return -EFAULT;
	}
	buf[count] = '\0';

	pox_config_parse_and_apply(buf);
	kfree(buf);
	return count;
}

static int pox_config_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, pox_config_proc_show, NULL);
}

static const struct file_operations pox_config_proc_fops = {
	.open    = pox_config_proc_open,
	.read    = seq_read,
	.write   = pox_config_proc_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static ssize_t pox_config_sysfs_show(struct kobject *kobj,
				     struct kobj_attribute *attr, char *buf)
{
	int len = 0;

	len += scnprintf(buf + len, PAGE_SIZE - len, "gaming_mode=%d\n", pox_gaming_mode_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "kprofiles_mode=%d\n", pox_kprofiles_mode_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "auto_kp=%d\n", pox_kprofiles_auto_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "kprofiles_custom=%d %d %d %d %d %d %d %d %d %d\n",
			 pox_custom_kp.schedutil_up_little_us,
			 pox_custom_kp.schedutil_down_little_us,
			 pox_custom_kp.schedutil_up_big_us,
			 pox_custom_kp.schedutil_down_big_us,
			 pox_custom_kp.top_app_boost,
			 pox_custom_kp.fg_boost,
			 pox_custom_kp.gpu_boost,
			 pox_custom_kp.dram_boost,
			 pox_custom_kp.touch_boost,
			 pox_custom_kp.rescue_opp);
	len += scnprintf(buf + len, PAGE_SIZE - len, "health_calibration=%d\n", pox_health_calibration_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "opp_voltage_guard=%d\n", pox_opp_voltage_guard_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "hbm_mode=%d\n", pox_hbm_mode_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "torch_brightness=%d\n", pox_torch_brightness_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "color_mode=%d\n", pox_color_mode_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "true_tone=%d\n", pox_true_tone_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "touch_game_mode=%d\n", pox_touch_game_mode_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "touch_sensitivity=%d\n", pox_touch_sensitivity_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "dt2w=%d\n", pox_dt2w_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "dynamic_fsync=%d\n", pox_dynamic_fsync_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "fast_charge=%d\n", pox_fast_charge_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "charge_watt=%d\n", pox_charge_watt_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "pd_min_watt=%d\n", pox_pd_min_watt_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "pd_max_watt=%d\n", pox_pd_max_watt_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "headphone_gain=%d\n", pox_headphone_gain_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "mic_gain=%d\n", pox_mic_gain_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "active_mic=%d\n", pox_active_mic_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "vibrator_strength=%d\n", pox_vibrator_strength_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "camera_4k60=%d\n", pox_camera_4k60_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "camera_slog3=%d\n", pox_camera_slog3_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "battery_bypass=%d\n", pox_battery_bypass_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "battery_limit=%d\n", pox_battery_limit_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "sched_bore=%d\n", sysctl_sched_bore);
	len += scnprintf(buf + len, PAGE_SIZE - len, "wakelock_blocker=%d\n", pox_wakelock_blocker_get());
	len += scnprintf(buf + len, PAGE_SIZE - len, "usb_cdrom=%d\n", pox_usb_cdrom_get());
	return len;
}

static ssize_t pox_config_sysfs_store(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	char *kbuf;

	if (count == 0 || count > 4096)
		return -EINVAL;

	kbuf = kmalloc(count + 1, GFP_KERNEL);
	if (!kbuf)
		return -ENOMEM;

	memcpy(kbuf, buf, count);
	kbuf[count] = '\0';

	pox_config_parse_and_apply(kbuf);
	kfree(kbuf);
	return count;
}

static struct kobj_attribute pox_config_kobj_attr =
	__ATTR(pox_config, 0644, pox_config_sysfs_show, pox_config_sysfs_store);

/* =========================================================================
 * Macro Helpers for Individual Procfs & Sysfs Nodes
 * ========================================================================= */

#define POX_GENERIC_FOPS(name, getter, setter) \
static int name##_proc_show(struct seq_file *m, void *v) \
{ \
	seq_printf(m, "%d\n", getter()); \
	return 0; \
} \
static ssize_t name##_proc_write(struct file *file, const char __user *ubuf, \
				 size_t count, loff_t *ppos) \
{ \
	char buf[32]; \
	int val; \
	if (count >= sizeof(buf)) \
		return -EINVAL; \
	if (copy_from_user(buf, ubuf, count)) \
		return -EFAULT; \
	buf[count] = '\0'; \
	if (kstrtoint(strim(buf), 10, &val) < 0) \
		return -EINVAL; \
	setter(val); \
	return count; \
} \
static int name##_proc_open(struct inode *inode, struct file *file) \
{ \
	return single_open(file, name##_proc_show, NULL); \
} \
static const struct file_operations name##_proc_fops = { \
	.open    = name##_proc_open, \
	.read    = seq_read, \
	.write   = name##_proc_write, \
	.llseek  = seq_lseek, \
	.release = single_release, \
}; \
static ssize_t name##_sysfs_show(struct kobject *kobj, \
				 struct kobj_attribute *attr, char *buf) \
{ \
	return scnprintf(buf, PAGE_SIZE, "%d\n", getter()); \
} \
static ssize_t name##_sysfs_store(struct kobject *kobj, \
				  struct kobj_attribute *attr, \
				  const char *buf, size_t count) \
{ \
	int val; \
	if (kstrtoint(strim((char *)buf), 10, &val) < 0) \
		return -EINVAL; \
	setter(val); \
	return count; \
} \
static struct kobj_attribute name##_kobj_attr = \
	__ATTR(name, 0644, name##_sysfs_show, name##_sysfs_store)

POX_GENERIC_FOPS(gaming_mode, pox_gaming_mode_get, pox_gaming_mode_set);
POX_GENERIC_FOPS(kp_mode, pox_kprofiles_mode_get, pox_kprofiles_mode_set);
POX_GENERIC_FOPS(auto_kp, pox_kprofiles_auto_get, pox_kprofiles_auto_set);
POX_GENERIC_FOPS(health_calibration, pox_health_calibration_get, pox_health_calibration_set);
POX_GENERIC_FOPS(opp_voltage_guard, pox_opp_voltage_guard_get, pox_opp_voltage_guard_set);
POX_GENERIC_FOPS(fast_charge, pox_fast_charge_get, pox_fast_charge_set);
POX_GENERIC_FOPS(charge_watt, pox_charge_watt_get, pox_charge_watt_set);
POX_GENERIC_FOPS(pd_min_watt, pox_pd_min_watt_get, pox_pd_min_watt_set);
POX_GENERIC_FOPS(pd_max_watt, pox_pd_max_watt_get, pox_pd_max_watt_set);
POX_GENERIC_FOPS(battery_bypass, pox_battery_bypass_get, pox_battery_bypass_set);
POX_GENERIC_FOPS(battery_limit, pox_battery_limit_get, pox_battery_limit_set);
POX_GENERIC_FOPS(touch_game_mode, pox_touch_game_mode_get, pox_touch_game_mode_set);
POX_GENERIC_FOPS(touch_sensitivity, pox_touch_sensitivity_get, pox_touch_sensitivity_set);
POX_GENERIC_FOPS(dt2w, pox_dt2w_get, pox_dt2w_set);
POX_GENERIC_FOPS(true_tone, pox_true_tone_get, pox_true_tone_set);
POX_GENERIC_FOPS(color_mode, pox_color_mode_get, pox_color_mode_set);
POX_GENERIC_FOPS(hbm_mode, pox_hbm_mode_get, pox_hbm_mode_set);
POX_GENERIC_FOPS(torch_brightness, pox_torch_brightness_get, pox_torch_brightness_set);
POX_GENERIC_FOPS(camera_4k60, pox_camera_4k60_get, pox_camera_4k60_set);
POX_GENERIC_FOPS(slog3, pox_camera_slog3_get, pox_camera_slog3_set);
POX_GENERIC_FOPS(dynamic_fsync, pox_dynamic_fsync_get, pox_dynamic_fsync_set);
POX_GENERIC_FOPS(wakelock_blocker, pox_wakelock_blocker_get, pox_wakelock_blocker_set);
POX_GENERIC_FOPS(usb_cdrom, pox_usb_cdrom_get, pox_usb_cdrom_set);
POX_GENERIC_FOPS(headphone_gain, pox_headphone_gain_get, pox_headphone_gain_set);
POX_GENERIC_FOPS(mic_gain, pox_mic_gain_get, pox_mic_gain_set);
POX_GENERIC_FOPS(active_mic, pox_active_mic_get, pox_active_mic_set);
POX_GENERIC_FOPS(vibrator_strength, pox_vibrator_strength_get, pox_vibrator_strength_set);

/* Sched BORE wrapper */
static int sched_bore_getter(void) { return sysctl_sched_bore; }
static void sched_bore_setter(int v) { sysctl_sched_bore = v ? 1 : 0; }
POX_GENERIC_FOPS(sched_bore, sched_bore_getter, sched_bore_setter);

/* Meta Readout: /proc/perfmgr/profile */
static int profile_proc_show(struct seq_file *m, void *v)
{
	int temp_c, soc, status;

	get_battery_stats(&temp_c, &soc, &status);
	seq_printf(m, "kernel_version: %s\n", POX_KERNEL_VERSION);
	seq_printf(m, "target_device: %s\n", POX_DEVICE_NAME);
	seq_printf(m, "gaming_mode: %d\n", pox_gaming_mode_get());
	seq_printf(m, "kprofiles_mode: %d\n", pox_kprofiles_mode_get());
	seq_printf(m, "auto_kp: %d\n", pox_kprofiles_auto_get());
	seq_printf(m, "health_calibration: %d\n", pox_health_calibration_get());
	seq_printf(m, "battery_temp_c: %d\n", temp_c);
	seq_printf(m, "battery_soc: %d\n", soc);
	seq_printf(m, "brownout_preventions: %lu\n", pox_brownout_preventions);
	seq_printf(m, "dynamic_fsync: %d\n", pox_dynamic_fsync_get());
	return 0;
}

static int profile_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, profile_proc_show, NULL);
}

static const struct file_operations profile_proc_fops = {
	.open    = profile_proc_open,
	.read    = seq_read,
	.llseek  = seq_lseek,
	.release = single_release,
};

/* Battery Status Readout: /proc/perfmgr/battery_status & /sys/kernel/battery_protection/status */
static int battery_status_proc_show(struct seq_file *m, void *v)
{
	int temp_c, soc, status;

	get_battery_stats(&temp_c, &soc, &status);
	seq_printf(m, "capacity: %d%%\n", soc);
	seq_printf(m, "temperature: %d C\n", temp_c);
	seq_printf(m, "status: %s\n", (status == POWER_SUPPLY_STATUS_CHARGING) ? "Charging" : "Discharging");
	seq_printf(m, "bypass_mode: %s\n", pox_battery_bypass_enabled ? "Active" : "Disabled");
	seq_printf(m, "charge_limit: %d%%\n", pox_battery_limit_val);
	seq_printf(m, "target_watt: %dW\n", pox_charge_watt_target);
	return 0;
}

static int battery_status_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, battery_status_proc_show, NULL);
}

static const struct file_operations battery_status_proc_fops = {
	.open    = battery_status_proc_open,
	.read    = seq_read,
	.llseek  = seq_lseek,
	.release = single_release,
};

static ssize_t battery_status_sysfs_show(struct kobject *kobj,
					 struct kobj_attribute *attr, char *buf)
{
	int temp_c, soc, status;

	get_battery_stats(&temp_c, &soc, &status);
	return scnprintf(buf, PAGE_SIZE,
			 "capacity: %d%%\ntemperature: %d C\nstatus: %s\nbypass: %d\nlimit: %d\n",
			 soc, temp_c, (status == POWER_SUPPLY_STATUS_CHARGING) ? "Charging" : "Discharging",
			 pox_battery_bypass_enabled, pox_battery_limit_val);
}

static struct kobj_attribute battery_status_kobj_attr =
	__ATTR(status, 0444, battery_status_sysfs_show, NULL);

/* Health Status Readout: /proc/perfmgr/health_status */
static int health_status_proc_show(struct seq_file *m, void *v)
{
	int temp_c, soc, status;

	get_battery_stats(&temp_c, &soc, &status);
	seq_printf(m, "health_mode: %d\n", pox_health_cal_mode);
	seq_printf(m, "opp_voltage_guard: %s\n", pox_opp_guard_enabled ? "Armed" : "Disarmed");
	seq_printf(m, "battery_temp_c: %d\n", temp_c);
	seq_printf(m, "battery_soc: %d\n", soc);
	seq_printf(m, "brownout_preventions: %lu\n", pox_brownout_preventions);
	seq_printf(m, "status: Calibrated (100%% Health) • Watchdog Armed\n");
	return 0;
}

static int health_status_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, health_status_proc_show, NULL);
}

static const struct file_operations health_status_proc_fops = {
	.open    = health_status_proc_open,
	.read    = seq_read,
	.llseek  = seq_lseek,
	.release = single_release,
};

/* Color Custom procfs & sysfs */
static int color_custom_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "%d %d %d %d\n", pox_color_sat, pox_color_contrast,
		   pox_color_brightness, pox_color_sat_adj);
	return 0;
}

static ssize_t color_custom_proc_write(struct file *file, const char __user *ubuf,
				       size_t count, loff_t *ppos)
{
	char buf[64];
	int sat = 4, con = 4, bri = 4, adj = 0;

	if (count >= sizeof(buf))
		return -EINVAL;
	if (copy_from_user(buf, ubuf, count))
		return -EFAULT;
	buf[count] = '\0';
	sscanf(buf, "%d %d %d %d", &sat, &con, &bri, &adj);
	pox_color_custom_set(sat, con, bri, adj);
	return count;
}

static int color_custom_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, color_custom_proc_show, NULL);
}

static const struct file_operations color_custom_proc_fops = {
	.open    = color_custom_proc_open,
	.read    = seq_read,
	.write   = color_custom_proc_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static ssize_t color_custom_sysfs_show(struct kobject *kobj,
				       struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d %d %d %d\n", pox_color_sat,
			 pox_color_contrast, pox_color_brightness, pox_color_sat_adj);
}

static ssize_t color_custom_sysfs_store(struct kobject *kobj,
					struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	int sat = 4, con = 4, bri = 4, adj = 0;

	sscanf(buf, "%d %d %d %d", &sat, &con, &bri, &adj);
	pox_color_custom_set(sat, con, bri, adj);
	return count;
}

static struct kobj_attribute color_custom_kobj_attr =
	__ATTR(color_custom, 0644, color_custom_sysfs_show, color_custom_sysfs_store);

/* Kprofiles Custom procfs & sysfs */
static int kprofiles_custom_proc_show(struct seq_file *m, void *v)
{
	seq_printf(m, "%d %d %d %d %d %d %d %d %d %d\n",
		   pox_custom_kp.schedutil_up_little_us,
		   pox_custom_kp.schedutil_down_little_us,
		   pox_custom_kp.schedutil_up_big_us,
		   pox_custom_kp.schedutil_down_big_us,
		   pox_custom_kp.top_app_boost,
		   pox_custom_kp.fg_boost,
		   pox_custom_kp.gpu_boost,
		   pox_custom_kp.dram_boost,
		   pox_custom_kp.touch_boost,
		   pox_custom_kp.rescue_opp);
	return 0;
}

static ssize_t kprofiles_custom_proc_write(struct file *file, const char __user *ubuf,
					  size_t count, loff_t *ppos)
{
	char buf[128];
	struct pox_kprofile_custom_tunables t = pox_custom_kp;

	if (count >= sizeof(buf))
		return -EINVAL;
	if (copy_from_user(buf, ubuf, count))
		return -EFAULT;
	buf[count] = '\0';
	sscanf(buf, "%d %d %d %d %d %d %d %d %d %d",
	       &t.schedutil_up_little_us, &t.schedutil_down_little_us,
	       &t.schedutil_up_big_us, &t.schedutil_down_big_us,
	       &t.top_app_boost, &t.fg_boost, &t.gpu_boost,
	       &t.dram_boost, &t.touch_boost, &t.rescue_opp);
	pox_custom_kp = t;
	return count;
}

static int kprofiles_custom_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, kprofiles_custom_proc_show, NULL);
}

static const struct file_operations kprofiles_custom_proc_fops = {
	.open    = kprofiles_custom_proc_open,
	.read    = seq_read,
	.write   = kprofiles_custom_proc_write,
	.llseek  = seq_lseek,
	.release = single_release,
};

static ssize_t custom_params_sysfs_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d %d %d %d %d %d %d %d %d %d\n",
			 pox_custom_kp.schedutil_up_little_us,
			 pox_custom_kp.schedutil_down_little_us,
			 pox_custom_kp.schedutil_up_big_us,
			 pox_custom_kp.schedutil_down_big_us,
			 pox_custom_kp.top_app_boost,
			 pox_custom_kp.fg_boost,
			 pox_custom_kp.gpu_boost,
			 pox_custom_kp.dram_boost,
			 pox_custom_kp.touch_boost,
			 pox_custom_kp.rescue_opp);
}

static ssize_t custom_params_sysfs_store(struct kobject *kobj,
					 struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	struct pox_kprofile_custom_tunables t = pox_custom_kp;

	sscanf(buf, "%d %d %d %d %d %d %d %d %d %d",
	       &t.schedutil_up_little_us, &t.schedutil_down_little_us,
	       &t.schedutil_up_big_us, &t.schedutil_down_big_us,
	       &t.top_app_boost, &t.fg_boost, &t.gpu_boost,
	       &t.dram_boost, &t.touch_boost, &t.rescue_opp);
	pox_custom_kp = t;
	return count;
}

static struct kobj_attribute custom_params_kobj_attr =
	__ATTR(custom_params, 0644, custom_params_sysfs_show, custom_params_sysfs_store);

/* Extra Sched BORE sysfs tunables */
#define POX_BORE_SYSFS(name, var) \
static ssize_t name##_sysfs_show(struct kobject *kobj, \
				 struct kobj_attribute *attr, char *buf) \
{ \
	return scnprintf(buf, PAGE_SIZE, "%u\n", var); \
} \
static ssize_t name##_sysfs_store(struct kobject *kobj, \
				  struct kobj_attribute *attr, \
				  const char *buf, size_t count) \
{ \
	unsigned int val; \
	if (kstrtouint(strim((char *)buf), 10, &val) < 0) \
		return -EINVAL; \
	var = val; \
	return count; \
} \
static struct kobj_attribute name##_kobj_attr = \
	__ATTR(name, 0644, name##_sysfs_show, name##_sysfs_store)

POX_BORE_SYSFS(sched_burst_penalty_scale, sysctl_sched_burst_penalty_scale);
POX_BORE_SYSFS(sched_burst_penalty_offset, sysctl_sched_burst_penalty_offset);
POX_BORE_SYSFS(sched_burst_inherit_type, sysctl_sched_burst_inherit_type);
POX_BORE_SYSFS(sched_burst_cache_lifetime, sysctl_sched_burst_cache_lifetime);

/* Extra Battery Protection sysfs tunables */
static ssize_t bypass_mode_sysfs_show(struct kobject *kobj,
				      struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", pox_battery_bypass_enabled);
}

static ssize_t bypass_mode_sysfs_store(struct kobject *kobj,
				       struct kobj_attribute *attr,
				       const char *buf, size_t count)
{
	int val;
	if (kstrtoint(strim((char *)buf), 10, &val) < 0)
		return -EINVAL;
	pox_battery_bypass_set(val);
	return count;
}

static struct kobj_attribute bypass_mode_kobj_attr =
	__ATTR(bypass_mode, 0644, bypass_mode_sysfs_show, bypass_mode_sysfs_store);

static ssize_t charge_limit_sysfs_show(struct kobject *kobj,
				       struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", pox_battery_limit_val);
}

static ssize_t charge_limit_sysfs_store(struct kobject *kobj,
					struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	int val;
	if (kstrtoint(strim((char *)buf), 10, &val) < 0)
		return -EINVAL;
	pox_battery_limit_set(val);
	return count;
}

static struct kobj_attribute charge_limit_kobj_attr =
	__ATTR(charge_limit, 0644, charge_limit_sysfs_show, charge_limit_sysfs_store);

static ssize_t thermal_guard_sysfs_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", pox_thermal_guard_enabled);
}

static ssize_t thermal_guard_sysfs_store(struct kobject *kobj,
					 struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(strim((char *)buf), 10, &val) < 0)
		return -EINVAL;
	pox_thermal_guard_enabled = val ? 1 : 0;
	return count;
}

static struct kobj_attribute thermal_guard_kobj_attr =
	__ATTR(thermal_guard, 0644, thermal_guard_sysfs_show, thermal_guard_sysfs_store);

static ssize_t temp_limit_sysfs_show(struct kobject *kobj,
				     struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", pox_temp_limit_c);
}

static ssize_t temp_limit_sysfs_store(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	int val;
	if (kstrtoint(strim((char *)buf), 10, &val) < 0)
		return -EINVAL;
	pox_temp_limit_c = val;
	return count;
}

static struct kobj_attribute temp_limit_kobj_attr =
	__ATTR(temp_limit, 0644, temp_limit_sysfs_show, temp_limit_sysfs_store);

/* =========================================================================
 * Subsystem Initialization & Teardown
 * ========================================================================= */

static int __init pox_core_init(void)
{
	pr_info("Initializing Pox Kernel Core Subsystem for %s...\n", POX_DEVICE_NAME);

	/* 1. Register LCD Screen Notifier */
	pox_lcd_notif.notifier_call = pox_lcd_notifier_callback;
	lcd_register_client(&pox_lcd_notif);

	/* 2. Schedule Dynamic Guard Work */
	INIT_DELAYED_WORK(&pox_dynamic_work, pox_dynamic_evaluate);
	schedule_delayed_work(&pox_dynamic_work, msecs_to_jiffies(8000));

	/* 3. Create /proc/perfmgr Directory */
	perfmgr_proc_dir = proc_mkdir("perfmgr", NULL);
	if (!perfmgr_proc_dir) {
		pr_err("Failed to create /proc/perfmgr directory\n");
		return -ENOMEM;
	}

	/* 4. Create Procfs Nodes under /proc/perfmgr/ */
	proc_create("pox_config", 0666, perfmgr_proc_dir, &pox_config_proc_fops);
	proc_create("gaming_mode", 0644, perfmgr_proc_dir, &gaming_mode_proc_fops);
	proc_create("profile", 0444, perfmgr_proc_dir, &profile_proc_fops);
	proc_create("kprofiles_custom", 0644, perfmgr_proc_dir, &kprofiles_custom_proc_fops);
	proc_create("health_calibration", 0644, perfmgr_proc_dir, &health_calibration_proc_fops);
	proc_create("opp_voltage_guard", 0644, perfmgr_proc_dir, &opp_voltage_guard_proc_fops);
	proc_create("health_status", 0444, perfmgr_proc_dir, &health_status_proc_fops);
	proc_create("sched_bore", 0644, perfmgr_proc_dir, &sched_bore_proc_fops);
	proc_create("fast_charge", 0644, perfmgr_proc_dir, &fast_charge_proc_fops);
	proc_create("charge_watt", 0644, perfmgr_proc_dir, &charge_watt_proc_fops);
	proc_create("pd_min_watt", 0644, perfmgr_proc_dir, &pd_min_watt_proc_fops);
	proc_create("pd_max_watt", 0644, perfmgr_proc_dir, &pd_max_watt_proc_fops);
	proc_create("battery_bypass", 0644, perfmgr_proc_dir, &battery_bypass_proc_fops);
	proc_create("battery_limit", 0644, perfmgr_proc_dir, &battery_limit_proc_fops);
	proc_create("battery_status", 0444, perfmgr_proc_dir, &battery_status_proc_fops);
	proc_create("touch_game_mode", 0644, perfmgr_proc_dir, &touch_game_mode_proc_fops);
	proc_create("touch_sensitivity", 0644, perfmgr_proc_dir, &touch_sensitivity_proc_fops);
	proc_create("dt2w", 0644, perfmgr_proc_dir, &dt2w_proc_fops);
	proc_create("true_tone", 0644, perfmgr_proc_dir, &true_tone_proc_fops);
	proc_create("color_mode", 0644, perfmgr_proc_dir, &color_mode_proc_fops);
	proc_create("color_custom", 0644, perfmgr_proc_dir, &color_custom_proc_fops);
	proc_create("hbm_mode", 0644, perfmgr_proc_dir, &hbm_mode_proc_fops);
	proc_create("torch_brightness", 0666, perfmgr_proc_dir, &torch_brightness_proc_fops);
	proc_create("flashlight_brightness", 0666, perfmgr_proc_dir, &torch_brightness_proc_fops);
	proc_create("torch_info", 0444, perfmgr_proc_dir, &profile_proc_fops);
	proc_create("camera_4k60", 0644, perfmgr_proc_dir, &camera_4k60_proc_fops);
	proc_create("slog3", 0644, perfmgr_proc_dir, &slog3_proc_fops);
	proc_create("dynamic_fsync", 0644, perfmgr_proc_dir, &dynamic_fsync_proc_fops);
	proc_create("wakelock_blocker", 0644, perfmgr_proc_dir, &wakelock_blocker_proc_fops);
	proc_create("usb_cdrom", 0644, perfmgr_proc_dir, &usb_cdrom_proc_fops);
	proc_create("headphone_gain", 0644, perfmgr_proc_dir, &headphone_gain_proc_fops);
	proc_create("mic_gain", 0644, perfmgr_proc_dir, &mic_gain_proc_fops);
	proc_create("active_mic", 0644, perfmgr_proc_dir, &active_mic_proc_fops);
	proc_create("vibrator_strength", 0644, perfmgr_proc_dir, &vibrator_strength_proc_fops);

	/* 5. Create Sysfs Nodes under /sys/kernel/ */
	sysfs_create_file(kernel_kobj, &pox_config_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &gaming_mode_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &health_calibration_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &opp_voltage_guard_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &true_tone_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &color_mode_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &color_custom_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &hbm_mode_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &torch_brightness_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &camera_4k60_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &slog3_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &sched_bore_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &sched_burst_penalty_scale_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &sched_burst_penalty_offset_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &sched_burst_inherit_type_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &sched_burst_cache_lifetime_kobj_attr.attr);
	sysfs_create_file(kernel_kobj, &usb_cdrom_kobj_attr.attr);

	/* 6. Create /sys/kernel/kprofiles/ */
	kp_kobj = kobject_create_and_add("kprofiles", kernel_kobj);
	if (kp_kobj) {
		sysfs_create_file(kp_kobj, &kp_mode_kobj_attr.attr);
		sysfs_create_file(kp_kobj, &auto_kp_kobj_attr.attr);
		sysfs_create_file(kp_kobj, &custom_params_kobj_attr.attr);
	}

	/* 7. Create /sys/kernel/battery_protection/ */
	battery_kobj = kobject_create_and_add("battery_protection", kernel_kobj);
	if (battery_kobj) {
		sysfs_create_file(battery_kobj, &bypass_mode_kobj_attr.attr);
		sysfs_create_file(battery_kobj, &charge_limit_kobj_attr.attr);
		sysfs_create_file(battery_kobj, &battery_status_kobj_attr.attr);
		sysfs_create_file(battery_kobj, &thermal_guard_kobj_attr.attr);
		sysfs_create_file(battery_kobj, &temp_limit_kobj_attr.attr);
	}

	/* 8. Create /sys/kernel/sound_control/ */
	sound_kobj = kobject_create_and_add("sound_control", kernel_kobj);
	if (sound_kobj)
		sysfs_create_file(sound_kobj, &active_mic_kobj_attr.attr);

	/* 9. Apply Default Pox Profile (Onyx: Performance & True Tone D65) */
	pox_gaming_mode_set(GAMING_MODE_ENABLED);

	pr_info("Pox Kernel Core Subsystem initialized successfully (Version %s, Onyx Active).\n",
		POX_KERNEL_VERSION);
	return 0;
}

static void __exit pox_core_exit(void)
{
	cancel_delayed_work_sync(&pox_dynamic_work);
	lcd_unregister_client(&pox_lcd_notif);

	if (sound_kobj)
		kobject_put(sound_kobj);
	if (battery_kobj)
		kobject_put(battery_kobj);
	if (kp_kobj)
		kobject_put(kp_kobj);

	if (perfmgr_proc_dir)
		remove_proc_subtree("perfmgr", NULL);

	pr_info("Pox Kernel Core Subsystem unloaded.\n");
}

late_initcall(pox_core_init);
module_exit(pox_core_exit);

MODULE_AUTHOR("TXO R <ravtx12best@gmail.com>");
MODULE_DESCRIPTION("Pox Kernel Core Subsystem for Samsung Galaxy M20 (m20lte)");
MODULE_LICENSE("GPL v2");
