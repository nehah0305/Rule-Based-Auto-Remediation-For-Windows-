"""
Root Cause Variant Detection System

Enables classification of errors with the same event_id but different root causes,
allowing precise and targeted remediation for each variant.
"""

import re
import json
from datetime import datetime
from enum import Enum


class VariantConfidence(Enum):
    """Confidence levels for root cause detection."""
    CERTAIN = 100        # Definitive indicators found
    HIGH = 80            # Strong indicators match
    MEDIUM = 60          # Multiple weak indicators match
    LOW = 40             # Single weak indicator or partial match
    UNKNOWN = 0          # No indicators detected


class RootCauseVariant:
    """Represents a detected root cause variant for an error."""
    
    def __init__(self, variant_id, label, description, confidence):
        self.variant_id = variant_id
        self.label = label                      # e.g., "HighCpuUsage", "DiskFull", "MemoryLeak"
        self.description = description
        self.confidence = confidence            # VariantConfidence enum value
        self.matched_indicators = []            # List of indicators that matched
        self.timestamp = datetime.utcnow().isoformat()

    def to_dict(self):
        return {
            'variant_id': self.variant_id,
            'label': self.label,
            'description': self.description,
            'confidence': self.confidence.value,
            'confidence_name': self.confidence.name,
            'matched_indicators': self.matched_indicators,
            'timestamp': self.timestamp,
        }


class RootCauseAnalyzer:
    """
    Analyzes event messages and metadata to detect root cause variants.
    
    Patterns are defined per event_id with:
    - indicator_patterns: list of (regex, weight) tuples for message analysis
    - message_keywords: high-certainty keywords indicating root cause
    - context_fields: check severity, category, or other metadata
    """
    
    def __init__(self):
        # Variant pattern database: event_id -> list of variant definitions
        self.variant_patterns = {}
        self._initialize_default_patterns()
    
    def _initialize_default_patterns(self):
        """Initialize common error variant patterns."""
        
        # Example: Error 1003 (Service Crash) variants
        self.variant_patterns[1003] = [
            {
                'variant_id': 'svc_crash_high_memory',
                'label': 'HighMemoryUsage',
                'description': 'Service crash due to excessive memory consumption',
                'message_patterns': [
                    (r'(?i)(out of memory|memory exhausted|insufficient memory)', 3),
                    (r'(?i)(heap|memory leak|memory allocation)', 2),
                    (r'memory', 1),
                ],
                'required_keywords': [],  # At least one must be present for CERTAIN
                'context_checks': [
                    {'field': 'severity', 'values': ['error', 'critical'], 'weight': 1},
                ],
            },
            {
                'variant_id': 'svc_crash_resource_lock',
                'label': 'DeadlockOrLock',
                'description': 'Service crash due to resource lock/deadlock',
                'message_patterns': [
                    (r'(?i)(deadlock|lock timeout|resource lock|blocked|timeout)', 3),
                    (r'(?i)(wait|acquire|lock|mutex)', 2),
                ],
                'required_keywords': ['deadlock', 'lock'],
                'context_checks': [],
            },
            {
                'variant_id': 'svc_crash_missing_dependency',
                'label': 'MissingDependency',
                'description': 'Service crash due to missing file/dependency',
                'message_patterns': [
                    (r'(?i)(not found|file not found|missing|cannot find)', 3),
                    (r'(?i)(dll|dependency|library|module)', 2),
                ],
                'required_keywords': ['not found', 'missing'],
                'context_checks': [],
            },
        ]
        
        # Example: Event 1000 (Application Error) variants
        self.variant_patterns[1000] = [
            {
                'variant_id': 'app_crash_exception',
                'label': 'UnhandledException',
                'description': 'Application crash due to unhandled exception',
                'message_patterns': [
                    (r'(?i)(exception|unhandled|error code|0x[0-9a-f]+)', 3),
                    (r'(?i)(access violation|segmentation fault)', 3),
                ],
                'required_keywords': [],
                'context_checks': [
                    {'field': 'severity', 'values': ['error', 'critical'], 'weight': 2},
                ],
            },
            {
                'variant_id': 'app_crash_plugin_failure',
                'label': 'PluginFailure',
                'description': 'Application crash due to plugin/extension failure',
                'message_patterns': [
                    (r'(?i)(plugin|extension|add-on|module)', 3),
                    (r'(?i)(load failed|initialize failed)', 3),
                ],
                'required_keywords': ['plugin', 'extension'],
                'context_checks': [],
            },
        ]
    
    def register_variant_pattern(self, event_id, variant_definition):
        """
        Register a custom variant pattern for an event_id.
        
        variant_definition structure:
        {
            'variant_id': 'unique_variant_id',
            'label': 'displayable_label',
            'description': 'what caused this variant',
            'message_patterns': [(regex_str, weight), ...],  # Higher weight = more confident
            'required_keywords': [keyword_list, ...],        # At least one needed for HIGH confidence
            'context_checks': [
                {'field': 'field_name', 'values': [values], 'weight': weight_int},
                ...
            ]
        }
        """
        if event_id not in self.variant_patterns:
            self.variant_patterns[event_id] = []
        self.variant_patterns[event_id].append(variant_definition)
    
    def analyze_event(self, event_dict):
        """
        Analyze an event and return all detected root cause variants
        with confidence scores.
        
        Returns list of RootCauseVariant objects, sorted by confidence (highest first).
        """
        event_id = event_dict.get('event_id')
        if event_id not in self.variant_patterns:
            return []
        
        message = (event_dict.get('message') or '').lower()
        detected_variants = []
        
        for variant_def in self.variant_patterns[event_id]:
            confidence_score = self._calculate_variant_confidence(
                message, event_dict, variant_def
            )
            
            if confidence_score.value > 0:  # Only return variants with some match
                variant = RootCauseVariant(
                    variant_id=variant_def['variant_id'],
                    label=variant_def['label'],
                    description=variant_def['description'],
                    confidence=confidence_score
                )
                detected_variants.append(variant)
        
        # Sort by confidence (highest first)
        detected_variants.sort(key=lambda v: v.confidence.value, reverse=True)
        return detected_variants
    
    def _calculate_variant_confidence(self, message, event_dict, variant_def):
        """Calculate confidence score for a variant against an event."""
        score = 0
        matched_indicators = []
        
        # ── Message pattern matching ──────────────────────────────────────
        for pattern_str, weight in variant_def.get('message_patterns', []):
            try:
                if re.search(pattern_str, message):
                    score += weight
                    matched_indicators.append(f'message_pattern: {pattern_str[:40]}...')
            except re.error:
                pass
        
        # ── Required keywords check ──────────────────────────────────────
        required_keywords = variant_def.get('required_keywords', [])
        if required_keywords:
            keyword_matched = any(kw.lower() in message for kw in required_keywords)
            if keyword_matched:
                score += 25  # Bonus for required keyword match
                matched_indicators.append('required_keyword_matched')
            else:
                # If required keywords not found, downgrade confidence
                if score > 0:
                    score = max(1, score // 2)  # Reduce confidence by half
        
        # ── Context field checks ──────────────────────────────────────────
        for context_check in variant_def.get('context_checks', []):
            field = context_check.get('field')
            allowed_values = context_check.get('values', [])
            weight = context_check.get('weight', 1)
            
            event_value = (event_dict.get(field) or '').lower()
            if any(v.lower() in event_value for v in allowed_values):
                score += weight * 10
                matched_indicators.append(f'context: {field}={event_value}')
        
        # ── Convert score to confidence level ──────────────────────────────
        if score >= 60:
            confidence = VariantConfidence.CERTAIN
        elif score >= 40:
            confidence = VariantConfidence.HIGH
        elif score >= 20:
            confidence = VariantConfidence.MEDIUM
        elif score > 0:
            confidence = VariantConfidence.LOW
        else:
            confidence = VariantConfidence.UNKNOWN
        
        return confidence


# Singleton instance
_analyzer = None


def get_analyzer():
    """Get or create the root cause analyzer instance."""
    global _analyzer
    if _analyzer is None:
        _analyzer = RootCauseAnalyzer()
    return _analyzer


def analyze_event(event_dict):
    """Convenience function to analyze an event."""
    return get_analyzer().analyze_event(event_dict)


def register_custom_variant(event_id, variant_definition):
    """Register a custom variant pattern."""
    return get_analyzer().register_variant_pattern(event_id, variant_definition)
