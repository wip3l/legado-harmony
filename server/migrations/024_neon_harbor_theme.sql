-- Original retro harbor theme; confirmed price: 90 Qingye points.
INSERT INTO theme_catalog (theme_id, display_name, price_points, valid_days, enabled)
VALUES ('neon-harbor', '霓港来信', 90, 365, TRUE)
ON CONFLICT (theme_id) DO NOTHING;
