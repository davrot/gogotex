// MongoDB Initialization Script for GoGoTeX
// This script runs on first container startup

// Switch to gogotex database
db = db.getSiblingDB('gogotex');

// Create users collection with indexes
if (!db.getCollectionNames().includes('users')) {
  db.createCollection('users');
}
db.users.createIndex({ 'oidcId': 1 }, { unique: true });
db.users.createIndex({ 'email': 1 }, { unique: true });
db.users.createIndex({ 'createdAt': 1 });

// Create projects collection with indexes
if (!db.getCollectionNames().includes('projects')) {
  db.createCollection('projects');
}
db.projects.createIndex({ 'owner': 1 });
db.projects.createIndex({ 'collaborators.userId': 1 });
db.projects.createIndex({ 'createdAt': -1 });
db.projects.createIndex({ 'name': 'text' });

// Create documents collection with indexes
if (!db.getCollectionNames().includes('documents')) {
  db.createCollection('documents');
}
db.documents.createIndex({ 'projectId': 1 });
db.documents.createIndex({ 'path': 1 });
db.documents.createIndex({ 'lastModifiedAt': -1 });

// Create sessions collection with TTL index
if (!db.getCollectionNames().includes('sessions')) {
  db.createCollection('sessions');
}
db.sessions.createIndex({ 'expiresAt': 1 }, { expireAfterSeconds: 0 });
db.sessions.createIndex({ 'userId': 1 });
db.sessions.createIndex({ 'token': 1 }, { unique: true });

// Create activity_logs collection with indexes
if (!db.getCollectionNames().includes('activity_logs')) {
  db.createCollection('activity_logs');
}
db.activity_logs.createIndex({ 'projectId': 1, 'timestamp': -1 });
db.activity_logs.createIndex({ 'userId': 1, 'timestamp': -1 });
db.activity_logs.createIndex({ 'timestamp': -1 });

print('✅ GoGoTeX database initialized successfully');
print('Collections created: users, projects, documents, sessions, activity_logs');