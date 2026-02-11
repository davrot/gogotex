// MongoDB Replica Set Initialization Script
// This configures the 3-node replica set

rs.initiate({
  _id: "gogolatex",
  members: [
    { _id: 0, host: "gogotex-mongodb-primary:27017", priority: 2 },
    { _id: 1, host: "gogotex-mongodb-secondary-1:27017", priority: 1 },
    { _id: 2, host: "gogotex-mongodb-secondary-2:27017", priority: 1 }
  ]
});

// Wait for replica set to stabilize
sleep(5000);

// Check status
print('✅ Replica set status:');
printjson(rs.status());