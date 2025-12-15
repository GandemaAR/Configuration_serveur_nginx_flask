# app.py – Version finale complète et fonctionnelle (décembre 2025)

import os
from flask import Flask, render_template, request, redirect, url_for, send_from_directory, session, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename

app = Flask(__name__)

# === Configuration ===
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'super-secret-key-change-me')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///site.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500 Mo max

# Extensions autorisées alignées avec file_types
ALLOWED_EXTENSIONS = {
    'pdf': 'pdf',
    'jpg': 'image', 'jpeg': 'image', 'png': 'image', 'gif': 'image', 'webp': 'image',
    'mp4': 'video', 'avi': 'video', 'mov': 'video', 'mkv': 'video', 'webm': 'video'
}

# Mot de passe admin (À CHANGER ABSOLUMENT !)
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', '@dmin123')

db = SQLAlchemy(app)

# Créer le dossier uploads s'il n'existe pas
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# === Modèles ===
class Category(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)

class Resource(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    filename = db.Column(db.String(200), nullable=False)
    file_type = db.Column(db.String(20), nullable=False)  # pdf, image, video
    category_id = db.Column(db.Integer, db.ForeignKey('category.id'), nullable=False)
    category = db.relationship('Category', backref='resources')

# === Création DB + catégorie par défaut ===
with app.app_context():
    db.create_all()
    if not Category.query.first():
        default = Category(name="Général")
        db.session.add(default)
        db.session.commit()

# === Fonctions utilitaires ===
def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_file_type_from_ext(ext):
    ext = ext.lower()
    if ext == 'pdf':
        return 'pdf'
    elif ext in ['jpg', 'jpeg', 'png', 'gif', 'webp']:
        return 'image'
    elif ext in ['mp4', 'avi', 'mov', 'mkv', 'webm']:
        return 'video'
    return None

# === Routes ===

@app.route('/')
def index():
    cat_id = request.args.get('cat')
    categories = Category.query.all()

    query = Resource.query
    if cat_id:
        query = query.filter_by(category_id=cat_id)
    resources = query.all()

    return render_template('client.html', resources=resources, categories=categories)

@app.route('/download/<int:resource_id>')
def download(resource_id):
    resource = Resource.query.get_or_404(resource_id)
    return send_from_directory(
        app.config['UPLOAD_FOLDER'],
        resource.filename,
        as_attachment=True
    )

@app.route('/view/<int:resource_id>')
def view(resource_id):
    resource = Resource.query.get_or_404(resource_id)
    return send_from_directory(
        app.config['UPLOAD_FOLDER'],
        resource.filename,
        as_attachment=False
    )

# === Admin Login ===
@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    if request.method == 'POST':
        if request.form['password'] == ADMIN_PASSWORD:
            session['admin'] = True
            return redirect('/admin')
        flash('Mot de passe incorrect', 'error')
    return render_template('login.html')

@app.route('/admin/logout')
def admin_logout():
    session.pop('admin', None)
    return redirect('/')

# === Page Admin ===
@app.route('/admin', methods=['GET', 'POST'])
def admin():
    if not session.get('admin'):
        return redirect('/admin/login')

    categories = Category.query.all()

    # === Gestion des POST ===
    if request.method == 'POST':
        action = request.form.get('action')

        # Créer une catégorie
        if action == 'create_category':
            name = request.form['new_category'].strip()
            if name and not Category.query.filter_by(name=name).first():
                db.session.add(Category(name=name))
                db.session.commit()
                flash('Catégorie créée avec succès !', 'success')
            else:
                flash('Nom invalide ou déjà utilisé.', 'error')

        # Uploader un fichier
        elif action == 'upload_resource':
            title = request.form.get('title')
            description = request.form.get('description')
            category_id = request.form.get('category')
            file = request.files.get('file')

            if not all([title, category_id, file]):
                flash('Tous les champs sont obligatoires.', 'error')
            elif not file or not allowed_file(file.filename):
                flash('Fichier invalide ou extension non autorisée.', 'error')
            else:
                ext = file.filename.rsplit('.', 1)[1].lower()
                file_type = get_file_type_from_ext(ext)
                if not file_type:
                    flash('Type de fichier non supporté.', 'error')
                else:
                    filename = secure_filename(file.filename)
                    file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                    file.save(file_path)

                    resource = Resource(
                        title=title,
                        description=description,
                        filename=filename,
                        file_type=file_type,
                        category_id=category_id
                    )
                    db.session.add(resource)
                    db.session.commit()
                    flash('Contenu ajouté avec succès !', 'success')

    # === Filtre par type (admin) ===
    type_filter = request.args.get('type')
    query = Resource.query
    if type_filter in ['pdf', 'image', 'video']:
        query = query.filter_by(file_type=type_filter)
    resources = query.all()

    return render_template('admin.html', resources=resources, categories=categories)

# === Suppression ===
@app.route('/admin/delete/<int:resource_id>', methods=['POST'])
def delete_resource(resource_id):
    if not session.get('admin'):
        return redirect('/admin/login')

    resource = Resource.query.get_or_404(resource_id)
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], resource.filename)
    if os.path.exists(file_path):
        os.remove(file_path)

    db.session.delete(resource)
    db.session.commit()
    flash('Contenu supprimé définitivement.', 'success')
    return redirect('/admin')

# === Lancement ===
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)