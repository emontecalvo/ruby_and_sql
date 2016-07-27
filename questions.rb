require 'singleton'
require 'sqlite3'

class QuestionsDatabase < SQLite3::Database
  include Singleton

  def initialize
    super('questions.db')
    self.type_translation = true #ask TA when here
    self.results_as_hash = true
  end
end

class User

  attr_accessor :lname, :fname
  attr_reader :id

  def initialize(options)
    @id = options["id"]
    @lname = options["lname"]
    @fname = options["fname"]
  end

  def self.find_by_id(id)
    id = QuestionsDatabase.instance.execute(<<-SQL, id)
    SELECT
      *
    FROM
      users
    WHERE
      id = ?

    SQL
    raise "not in database" if id.empty?
    User.new(id.first)
  end

  def self.find_by_name(fname, lname)
    name = QuestionsDatabase.instance.execute(<<-SQL, fname, lname)
      SELECT
        *
      FROM
        users
      WHERE
        fname = ? AND lname = ?
    SQL
    raise "not in database" if name.empty?
    User.new(name.first)
    # for instance that names are not unique, creat a map function
    # to return an array of user_objects with specified name (eg. "Mary Smith " or "John Smith")
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL, @fname, @lname)
      INSERT INTO
        users (fname, lname)
      VALUES
        (?, ?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL, @fname, @lname, @id)
      UPDATE
        users
      SET
        fname = ?, lname = ?
      WHERE
        id = ?
    SQL
  end

  def save
    if @id
      update
    else
      create
    end
  end

  def authored_questions
    Question.find_by_author_id(@id)
  end

  def authored_replies
    Reply.find_by_id(@id)
  end

  def followed_questions
    QuestionFollow.followed_questions_for_user_id(@id)
  end

  def liked_questions
    QuestionLike.liked_questions_for_user_id(@id)
  end

  def average_karma
    result = QuestionsDatabase.instance.execute(<<-SQL, @id)
      SELECT
        CAST (COUNT(questions.id) / COUNT(DISTINCT questions.id) AS FLOAT)
      FROM
        questions
      LEFT OUTER JOIN
        question_likes ON questions.id = question_likes.question_id
      WHERE
        questions.author_id = ?
    SQL
    result
  end

  # num of questions asked by a users
  # return number of likes on those questions

end

class Question

  attr_accessor :title, :body, :author_id

  def initialize(options)
    @id = options["id"]
    @title = options["title"]
    @body = options["body"]
    @author_id = options["author_id"]
  end

  def self.find_by_id(id)
    id = QuestionsDatabase.instance.execute(<<-SQL, id)
    SELECT
      *
    FROM
      questions
    WHERE
      id = ?
    SQL
    raise "not in database" if id.empty?
    Question.new(id.first)
  end

  def self.find_by_author_id(author_id)
    author = User.find_by_id(author_id)
    questions = QuestionsDatabase.instance.execute(<<-SQL, author_id)
      SELECT
        *
      FROM
        questions
      WHERE
        author_id = ?
    SQL
    questions.map { |question_hash| Question.new(question_hash) }
  end

  def self.most_liked(n)
    QuestionLike.most_liked_questions(n)
  end

  def self.most_followed(n)
    QuestionFollow.most_followed_questions(n)
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL, @title, @body, @author_id)
      INSERT INTO
        questions (title, body, author)
      VALUES
        (?, ?, ?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL, @title, @body, @author_id, @id)
      UPDATE
        questions
      SET
        title = ?, body = ?, author_id = ?
      WHERE
        id = ?
    SQL
  end

  def save
    if @id
      update
    else
      create
    end
  end



  def author
    User.find_by_id(@author_id)
  end

  def replies
    Reply.find_by_question_id(@id)
  end

  def followers
    QuestionFollow.followers_for_question_id(@id)
  end

  def likers
    QuestionLike.likers_for_question_id(@id)
  end

  def liked_questions(n)
    QuestionLike.num_likes_for_question_id(n)
  end

end

class QuestionFollow

  attr_accessor :user_id, :question_id

  def initialize(options)
    @id = options["id"]
    @user_id = options["user_id"]
    @question_id = options["question_id"]
  end

  def self.find_by_id(id)
    id = QuestionsDatabase.instance.execute(<<-SQL, id)
    SELECT
      *
    FROM
      questions_follows
    WHERE
      id = ?

    SQL
    raise "not in database" if id.empty?
    QuestionFollow.new(id.first)
  end

  def self.followers_for_question_id(question_id)
    users = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        users.*
      FROM
        question_follows
      JOIN
        questions ON questions.id = question_follows.question_id
      JOIN
        users ON users.id = question_follows.user_id
      WHERE
        questions.id = ?
    SQL
    users.map { |user_hash| User.new(user_hash) }
  end

  def self.followed_questions_for_user_id(user_id)
    questions = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        questions.*
      FROM
        question_follows
      JOIN
        questions ON questions.id = question_follows.question_id
      JOIN
        users ON users.id = question_follows.user_id
      WHERE
        users.id = ?
    SQL
    questions.map { |question_hash| Question.new(question_hash) }
  end

  def self.most_followed_questions(n)
    questions = QuestionsDatabase.instance.execute(<<-SQL, n)
      SELECT
        questions.*
      FROM
        questions
      JOIN
        question_follows ON questions.id = question_follows.question_id
      JOIN
        users ON users.id = question_follows.user_id
      GROUP BY
        questions.id
      ORDER BY
        COUNT(users.id) DESC
      LIMIT
        ?
    SQL
    questions.map { |question_hash| Question.new(question_hash) }
  end



end

class Reply

  attr_accessor :body, :parent_reply_id, :author_id, :question_id

  def initialize(options)
    @id = options["id"]
    @body = options["body"]
    @parent_reply_id = options["parent_reply_id"]
    @author_id = options['author_id']
    @question_id = options['question_id']
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL, @body, @parent_reply_id, @author_id, @question_id)
      INSERT INTO
        replies (body, parent_reply_id, author_id, question_id)
      VALUES
        (?, ?, ?, ?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL, @body, @parent_reply_id, @author_id, @question_id, @id)
      UPDATE
        replies
      SET
        body = ?, parent_reply_id = ?, author_id = ?, question_id = ?
      WHERE
        id = ?
    SQL
  end

  def save
    if @id
      update
    else
      create
    end
  end

  def self.find_by_id(id)
    id = QuestionsDatabase.instance.execute(<<-SQL, id)
    SELECT
      *
    FROM
      replies
    WHERE
      id = ?
    ORDER BY
      id

    SQL
    raise "not in database" if id.empty?
    Reply.new(id.first)
  end

  def self.find_by_user_id(user_id)
    replies = QuestionsDatabase.instance.execute(<<-SQL, user_id)
    SELECT
      *
    FROM
      replies
    WHERE
      author_id = ?
    SQL

    replies.map { |reply_hash| Reply.new(reply_hash) }
  end

  def self.find_by_question_id(question_id)
    replies = QuestionsDatabase.instance.execute(<<-SQL, question_id)
    SELECT
      *
    FROM
      replies
    WHERE
      question_id = ?
    SQL

    replies.map { |reply_hash| Reply.new(reply_hash) }
  end

  def self.find_by_parent_id(parent_id)
    parent = QuestionsDatabase.instance.execute(<<-SQL, parent_id)
      SELECT
        *
      FROM
        replies
      WHERE
        parent_reply_id = ?
    SQL
    Reply.new(parent.first)
  end

  def author
    User.find_by_id(@author_id)
  end

  def question
    Question.find_by_id(@question_id)
  end

  def parent_reply
    Reply.find_by_id(@parent_reply_id)
  end

  def child_replies
    Reply.find_by_parent_id(@id)
  end
end

class QuestionLike

  attr_accessor :user_id, :question_id

  def initialize(options)
    @id = options["id"]
    @user_id = options['user_id']
    @question_id = options['questions_id']
  end

  def self.find_by_id(id)
    id = QuestionsDatabase.instance.execute(<<-SQL, id)
    SELECT
      *
    FROM
      question_likes
    WHERE
      id = ?

    SQL
    raise "not in database" if id.empty?
    QuestionLike.new(id.first)
  end

  def self.likers_for_question_id(question_id)
    users = QuestionsDatabase.instance.execute(<<-SQL, question_id)
    SELECT
      users.*
    FROM
      users
    JOIN
      question_likes ON users.id = question_likes.user_id
    JOIN
      questions ON question_likes.question_id = questions.id
    WHERE
      questions.id = ?

    SQL

    users.map { |user_hash| User.new(user_hash) }
  end

  def self.num_likes_for_question_id(question_id)
    num = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        COUNT(*)
      FROM
        users
      JOIN
        question_likes ON users.id = question_likes.user_id
      JOIN
        questions ON question_likes.question_id = questions.id
      WHERE
        questions.id = ?
      GROUP BY
        questions.id
    SQL
    num.first.values[0]
  end

  def self.liked_questions_for_user_id(user_id)
    liked_questions = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        questions.*
      FROM
        questions
      JOIN
        question_likes ON question_likes.question_id = questions.id
      JOIN
        users ON users.id = question_likes.user_id
      WHERE
        users.id = ?
    SQL
    liked_questions.map { |liked_hash| Question.new(liked_hash) }
  end

  def self.most_liked_questions(n)
    most_liked = QuestionsDatabase.instance.execute(<<-SQL, n)
    SELECT
      questions.*
    FROM
      questions
    JOIN
      question_likes ON questions.id = question_likes.question_id
    JOIN
      users ON users.id = question_likes.user_id
    GROUP BY
      questions.id
    ORDER BY
      COUNT(*) DESC
    LIMIT
      ?
    SQL
    most_liked.map { |liked_hash| Question.new(liked_hash) }
  end

end
