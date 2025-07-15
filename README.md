# Intelligent Perk Assignment System for Travel Platform

This project implements a machine learning pipeline to automatically assign personalized travel perks (1–9) to users based on their booking behavior and profile data. It combines unsupervised clustering with supervised learning in a unified architecture, optimized for scalability and real-time application.

Overview
Component	Description
Model Architecture	Unified system combining PCA, KMeans clustering, and Random Forest classification
Clustering	4 user segments identified via KMeans after PCA (15 dimensions)
Classification	Random Forest predicts the most suitable perk_id using user features and cluster ID
Accuracy	95% overall, Macro-F1 score: 0.87
Real-time Capability	Designed for integration into live data pipelines
Maintenance	Centralized, low-maintenance architecture with versioned model and unified feature store

Pipeline Overview
Input Data
User booking history, session data, stay patterns, pricing metrics.

Clustering (Unsupervised)

Dimensionality reduction via PCA (15 components)

KMeans clustering (k=4, optimized using elbow and silhouette methods)

Output cluster used as a categorical feature (cluster_kmeans_4)

Classification (Supervised)

Target: perk_id (1–9), derived from business rules

Model: Random Forest with a wide feature set including cluster label

Top predictive features:

avg_price_per_room

sessions_with_hotel_booking

total_hotel_bookings

total_rooms_booked

num_hotel_stays

Evaluation

Confusion matrix shows strong separation, especially for perks 1, 4, 5, 6, and 7

Perks 2 and 3 underperform due to low sample size and feature overlap

Features
Behavior-based segmentation

Dynamic personalization for both new and existing users

Centralized logic via one model architecture

Scalable and production-ready

Extensible for API deployment and real-time scoring

Future Improvements
Improve classification for perks 2 and 3 via targeted data collection or synthetic sampling

Integrate SHAP for model explainability and case-level insights

Connect to production APIs for end-to-end automation

Implement continuous evaluation and feedback loops
