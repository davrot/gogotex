# LaTeX Collaborative Editor

## Overview
The LaTeX Collaborative Editor is a multi-user online editor that allows users to collaboratively create and edit LaTeX documents in real-time. The application leverages Go and Node.js for backend services, with a modern frontend built using React. It includes features such as real-time editing, commenting, change tracking, user authentication via OpenID Connect, and integration with Git for version control.

## Features
- **Real-time Editing**: Multiple users can edit documents simultaneously with live updates.
- **Commenting**: Users can leave comments on specific parts of the document for discussion.
- **Change Tracking**: Track changes made to the document and manage version control.
- **User Authentication**: Secure user authentication using OpenID Connect.
- **Git Integration**: Manage document versions and collaborate using Git.
- **LaTeX Compilation**: Compile LaTeX documents in a Dockerized environment.

## Architecture
The application is structured into several components:
- **Backend**: 
  - Go services for authentication, document management, and LaTeX compilation.
  - Node.js services for real-time collaboration and Git operations.
- **Frontend**: A React application that provides the user interface for editing documents, viewing comments, and tracking changes.
- **Database**: MongoDB for storing user and document data.
- **Caching**: Redis for managing session data and real-time updates.
- **File Storage**: MinIO for storing compiled LaTeX documents.
- **Containerization**: Docker for deploying services in isolated environments.

## Setup Instructions
1. **Clone the Repository**:
   ```
   git clone <repository-url>
   cd latex-collaborative-editor
   ```

2. **Install Dependencies**:
   - For Go services:
     ```
     cd backend/go-services
     go mod tidy
     ```
   - For Node.js services:
     ```
     cd backend/node-services/realtime-server
     npm install
     cd ../git-service
     npm install
     ```

3. **Configure Services**:
   - Update configuration files in the `config` directory as needed (e.g., MongoDB, Redis, MinIO).

4. **Build Docker Images**:
   ```
   docker-compose build
   ```

5. **Run the Application**:
   ```
   docker-compose up
   ```

## Usage
- Access the application through your web browser at `http://localhost:3000`.
- Create an account or log in using OpenID Connect.
- Start creating and editing LaTeX documents collaboratively.

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for details.