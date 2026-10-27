/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2026 Pox Kernel Project - TXO R
 *
 * Pox Kernel Core Subsystem for Samsung Galaxy M20 (universal7885 / m20lte)
 *
 * Provides unified Pox interfaces: Gaming Mode, Kprofiles, Battery Protection,
 * True Tone & Color Control, Health Calibration, Sched BORE, and Atomic Pox Config.
 */

#ifndef _POX_CORE_H
#define _POX_CORE_H

#include <linux/types.h>

#define POX_KERNEL_VERSION	"1.0.0-Beta-Onyx"
#define POX_DEVICE_NAME		"Samsung Galaxy M20 (m20lte)"

/* Gaming Mode Presets */
#define GAMING_MODE_POWERSAVE	(-1)
#define GAMING_MODE_DISABLED	0
#define GAMING_MODE_ENABLED	1
#define GAMING_MODE_EXTREME	2

/* Kprofiles Levels */
#define KPROFILES_DISABLED	0
#define KPROFILES_BATTERY	1
#define KPROFILES_BALANCED	2
#define KPROFILES_PERFORMANCE	3
#define KPROFILES_CUSTOM	4

/* Health Calibration Modes */
#define HEALTH_CAL_DISABLED	0
#define HEALTH_CAL_AUTO		1
#define HEALTH_CAL_PERF_GUARD	2
#define HEALTH_CAL_LONGEVITY	3

/* Color Modes */
#define COLOR_MODE_STANDARD	0
#define COLOR_MODE_REFERENCE	1
#define COLOR_MODE_SLOG3	2
#define COLOR_MODE_CUSTOM	3

struct pox_kprofile_custom_tunables {
	int schedutil_up_little_us;
	int schedutil_down_little_us;
	int schedutil_up_big_us;
	int schedutil_down_big_us;
	int top_app_boost;
	int fg_boost;
	int gpu_boost;
	int dram_boost;
	int touch_boost;
	int rescue_opp;
};

int pox_gaming_mode_set(int mode);
int pox_gaming_mode_get(void);
int pox_kprofiles_mode_set(int mode);
int pox_kprofiles_mode_get(void);
int pox_kprofiles_auto_set(int enable);
int pox_kprofiles_auto_get(void);
int pox_health_calibration_set(int mode);
int pox_health_calibration_get(void);
int pox_opp_voltage_guard_set(int enable);
int pox_opp_voltage_guard_get(void);
int pox_battery_bypass_set(int enable);
int pox_battery_bypass_get(void);
int pox_battery_limit_set(int limit);
int pox_battery_limit_get(void);
int pox_fast_charge_set(int enable);
int pox_fast_charge_get(void);
int pox_charge_watt_set(int watt);
int pox_charge_watt_get(void);
int pox_pd_min_watt_set(int watt);
int pox_pd_min_watt_get(void);
int pox_pd_max_watt_set(int watt);
int pox_pd_max_watt_get(void);
int pox_true_tone_set(int enable);
int pox_true_tone_get(void);
int pox_color_mode_set(int mode);
int pox_color_mode_get(void);
int pox_color_custom_set(int sat, int contrast, int brightness, int sat_adj);
void pox_color_custom_get(int *sat, int *contrast, int *brightness, int *sat_adj);
int pox_hbm_mode_set(int mode);
int pox_hbm_mode_get(void);
int pox_torch_brightness_set(int val);
int pox_torch_brightness_get(void);
int pox_camera_4k60_set(int force);
int pox_camera_4k60_get(void);
int pox_camera_slog3_set(int enable);
int pox_camera_slog3_get(void);
int pox_touch_game_mode_set(int enable);
int pox_touch_game_mode_get(void);
int pox_touch_sensitivity_set(int val);
int pox_touch_sensitivity_get(void);
int pox_dt2w_set(int enable);
int pox_dt2w_get(void);
int pox_dynamic_fsync_set(int enable);
int pox_dynamic_fsync_get(void);
int pox_wakelock_blocker_set(int enable);
int pox_wakelock_blocker_get(void);
int pox_usb_cdrom_set(int enable);
int pox_usb_cdrom_get(void);
int pox_headphone_gain_set(int gain);
int pox_headphone_gain_get(void);
int pox_mic_gain_set(int gain);
int pox_mic_gain_get(void);
int pox_active_mic_set(int mode);
int pox_active_mic_get(void);
int pox_vibrator_strength_set(int val);
int pox_vibrator_strength_get(void);

#endif /* _POX_CORE_H */
