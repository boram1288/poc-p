/* SPDX-License-Identifier: MIT */
#ifndef PVM_VISION_FIXTURE_H
#define PVM_VISION_FIXTURE_H

#include <stdint.h>

#define PVM_VISION_FIXTURE_MAGIC "PVMVIS10"
#define PVM_VISION_FIXTURE_VERSION UINT32_C(1)
#define PVM_VISION_FRAME_COUNT UINT32_C(30)
#define PVM_VISION_PAGE_SIZE UINT32_C(4096)
#define PVM_VISION_ACTIVE_SIZE UINT32_C(3072)
#define PVM_VISION_WIDTH UINT32_C(32)
#define PVM_VISION_HEIGHT UINT32_C(32)
#define PVM_VISION_STRIDE UINT32_C(96)
#define PVM_VISION_MAX_DETECTIONS UINT32_C(16)

struct pvm_vision_detection {
	uint32_t class_id;
	uint32_t confidence_q16;
	uint32_t xmin_q16;
	uint32_t ymin_q16;
	uint32_t xmax_q16;
	uint32_t ymax_q16;
};

struct pvm_vision_fixture_header {
	uint8_t magic[8];
	uint32_t version;
	uint32_t frame_count;
	uint32_t page_size;
	uint32_t max_detections;
	uint32_t source_width;
	uint32_t source_height;
	uint32_t active_size;
	uint32_t reserved;
	uint8_t video_sha256[32];
};

struct pvm_vision_oracle_record {
	uint32_t source_frame_index;
	uint32_t detection_count;
	uint32_t truncated;
	uint32_t reserved;
	uint8_t frame_sha256[32];
	struct pvm_vision_detection detections[PVM_VISION_MAX_DETECTIONS];
};

#endif
